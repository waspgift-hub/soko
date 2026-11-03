const crypto = require('crypto');
const axios = require('axios');
const nodemailer = require('nodemailer');
const { smsSafeForGateway, localizeEmailOtp } = require('./notif_lang');

const smtpTransporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST || 'smtp.gmail.com',
  port: parseInt(process.env.SMTP_PORT || '587'),
  secure: process.env.SMTP_SECURE === 'true',
  auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS },
});

async function sendSms(phone, message) {
  try {
    const apiKey = process.env.MESEJI_API_KEY;
    if (apiKey) {
      const digits = phone.replace(/\D/g, '');
      const local = digits.startsWith('255') ? '0' + digits.slice(3) : !digits.startsWith('0') ? '0' + digits : digits;
      const configured = process.env.MESEJI_SENDER_ID || 'MESEJI';
      const senders = configured === 'MESEJI' ? ['MESEJI'] : [configured, 'MESEJI'];
      for (const sender of senders) {
        try {
          const resp = await axios.post('https://meseji.co.tz/api/v1/sms/send', {
            sender_id: sender,
            message,
            contacts: local,
          }, {
            headers: { 'x-api-key': apiKey, 'Content-Type': 'application/json' },
            timeout: 15000,
          });
          console.log(`sendSms: ok sender=${sender} to ${local} batch=${resp.data?.batch_id || ''}`);
          return true;
        } catch (e) {
          const errBody = e.response?.data ? JSON.stringify(e.response.data) : e.message;
          console.error(`sendSms: sender ${sender} error: ${errBody}`);
        }
      }
    }
    console.error('sendSms: no SMS provider delivered (Meseji)');
    return false;
  } catch (e) {
    console.error('sendSms error:', e.message);
    return false;
  }
}

module.exports = function ({ admin, db }) {
  async function sendOtp(req, res) {
    try {
      const { phone } = req.body;
      if (!phone) return res.status(400).json({ error: 'Phone number is required' });
      if (!db) return res.status(503).json({ error: 'Database not configured' });

      const otp = crypto.randomInt(100000, 1000000).toString();
      const hashed = crypto.createHash('sha256').update(otp).digest('hex');
      const expiresAt = Date.now() + 10 * 60 * 1000;

      const cleanPhone = phone.replace(/\D/g, '');

      await db.collection('otp_codes').doc(cleanPhone).set({
        otpHash: hashed,
        expiresAt,
        used: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      const message = `OTP yako ni ${otp}. Inaisha kwa dakika 10.`;
      const langCode = ['sw', 'en', 'zh'].includes(req.body.langCode) ? req.body.langCode : 'sw';
      const sent = await sendSms(cleanPhone, smsSafeForGateway(langCode, message));

      await db.collection('otp_codes').doc(cleanPhone).update({
        smsSent: sent,
        smsAttemptedAt: admin.firestore.FieldValue.serverTimestamp(),
      }).catch(() => {});

      if (!sent) {
        console.error('/api/auth/send-otp: sendSms returned false for', cleanPhone);
        return res.status(502).json({ error: 'auth_otp_send_failed' });
      }

      res.json({ sent: true, message: 'OTP imetumwa kwa simu yako' });
    } catch (e) {
      console.error('/api/auth/send-otp error:', e.message);
      res.status(500).json({ error: 'auth_otp_send_failed' });
    }
  }

  async function verifyOtp(req, res) {
    try {
      const { phone, otp } = req.body;
      if (!phone || !otp) return res.status(400).json({ error: 'Phone and OTP are required' });
      if (!db) return res.status(503).json({ error: 'Database not configured' });

      const cleanPhone = phone.replace(/\D/g, '');
      const doc = await db.collection('otp_codes').doc(cleanPhone).get();
      if (!doc.exists) return res.status(400).json({ error: 'auth_otp_expired' });

      const data = doc.data();
      if (data.used) return res.status(400).json({ error: 'auth_otp_invalid' });
      if (Date.now() > data.expiresAt) return res.status(400).json({ error: 'auth_otp_expired' });

      const hashed = crypto.createHash('sha256').update(otp).digest('hex');
      if (hashed !== data.otpHash) return res.status(400).json({ error: 'auth_otp_invalid' });

      await doc.ref.update({ used: true });

      res.json({ valid: true });
    } catch (e) {
      console.error('/api/auth/verify-otp error:', e.message);
      res.status(500).json({ error: 'Internal server error' });
    }
  }

  async function sendEmailOtp(req, res) {
    try {
      const { email, langCode } = req.body;
      if (!email) return res.status(400).json({ error: 'Email is required' });
      if (!db) return res.status(503).json({ error: 'Database not configured' });

      const cleanEmail = email.trim().toLowerCase();
      const otp = crypto.randomInt(100000, 1000000).toString();
      const hashed = crypto.createHash('sha256').update(otp).digest('hex');
      const expiresAt = Date.now() + 10 * 60 * 1000;

      await db.collection('otp_codes').doc(cleanEmail).set({
        otpHash: hashed,
        expiresAt,
        used: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      const lang = ['sw', 'en', 'zh'].includes(langCode) ? langCode : 'sw';
      const copy = localizeEmailOtp(lang);

      const subject = copy.subject;
      const html = `<html><body style="font-family:Arial,sans-serif;padding:20px;max-width:600px;margin:0 auto"><h2 style="color:#40916C">${copy.heading}</h2><p>${copy.body}</p><p style="font-size:32px;font-weight:bold;letter-spacing:8px;color:#40916C">${otp}</p><p>${copy.expires}</p><hr style="border:none;border-top:1px solid #e0e0e0;margin:20px 0"/><p style="color:#999;font-size:12px">Soko Vibe</p></body></html>`;

      try {
        await smtpTransporter.sendMail({
          from: process.env.SMTP_FROM || 'Soko Vibe <waspgift@gmail.com>',
          to: cleanEmail,
          subject,
          html,
        });
        console.log(`[SMTP] email OTP sent to ${cleanEmail}`);
      } catch (e) {
        console.error('/api/auth/send-email-otp SMTP error:', e.message);
        return res.status(502).json({ error: 'auth_otp_send_failed' });
      }

      res.json({ sent: true, message: 'OTP imetumwa kwa barua pepe yako' });
    } catch (e) {
      console.error('/api/auth/send-email-otp error:', e.message);
      res.status(500).json({ error: 'auth_otp_send_failed' });
    }
  }

  async function verifyEmailOtp(req, res) {
    try {
      const { email, otp } = req.body;
      if (!email || !otp) return res.status(400).json({ error: 'Email and OTP are required' });
      if (!db) return res.status(503).json({ error: 'Database not configured' });

      const cleanEmail = email.trim().toLowerCase();
      const doc = await db.collection('otp_codes').doc(cleanEmail).get();
      if (!doc.exists) return res.status(400).json({ error: 'auth_otp_expired' });

      const data = doc.data();
      if (data.used) return res.status(400).json({ error: 'auth_otp_invalid' });
      if (Date.now() > data.expiresAt) return res.status(400).json({ error: 'auth_otp_expired' });

      const hashed = crypto.createHash('sha256').update(otp).digest('hex');
      if (hashed !== data.otpHash) return res.status(400).json({ error: 'auth_otp_invalid' });

      await doc.ref.update({ used: true });

      res.json({ valid: true });
    } catch (e) {
      console.error('/api/auth/verify-email-otp error:', e.message);
      res.status(500).json({ error: 'Internal server error' });
    }
  }

  async function checkPhone(req, res) {
    try {
      const { phone } = req.body;
      if (!phone) return res.status(400).json({ error: 'Phone is required' });
      if (!db) return res.status(503).json({ error: 'Database not configured' });

      const cleanPhone = phone.replace(/\D/g, '');
      const snap = await db.collection('users')
        .where('phone', 'in', [cleanPhone, `0${cleanPhone.slice(-9)}`, `+${cleanPhone}`])
        .limit(1)
        .get();

      res.json({ exists: !snap.empty });
    } catch (e) {
      console.error('/api/auth/check-phone error:', e.message);
      res.status(500).json({ error: 'Internal server error' });
    }
  }

  async function checkEmail(req, res) {
    try {
      const { email } = req.body;
      if (!email) return res.status(400).json({ error: 'Email is required' });
      if (!db) return res.status(503).json({ error: 'Database not configured' });

      const snap = await db.collection('users')
        .where('email', '==', email.trim().toLowerCase())
        .limit(1)
        .get();

      let exists = !snap.empty;
      if (!exists) {
        try {
          await admin.auth().getUserByEmail(email.trim().toLowerCase());
          exists = true;
        } catch (_) {}
      }

      res.json({ exists });
    } catch (e) {
      console.error('/api/auth/check-email error:', e.message);
      res.status(500).json({ error: 'Internal server error' });
    }
  }

  async function resetPasswordByPhone(req, res) {
    try {
      const { phone, otp, newPassword } = req.body;
      if (!phone || !otp || !newPassword) {
        return res.status(400).json({ error: 'Phone, OTP, and new password are required' });
      }
      if (newPassword.length < 8) {
        return res.status(400).json({ error: 'Password must be at least 8 characters' });
      }
      if (!db) return res.status(503).json({ error: 'Database not configured' });

      const cleanPhone = phone.replace(/\D/g, '');

      const otpDoc = await db.collection('otp_codes').doc(cleanPhone).get();
      if (!otpDoc.exists) return res.status(400).json({ error: 'auth_otp_expired' });

      const otpData = otpDoc.data();
      if (otpData.used) return res.status(400).json({ error: 'auth_otp_invalid' });
      if (Date.now() > otpData.expiresAt) return res.status(400).json({ error: 'auth_otp_expired' });

      const hashed = crypto.createHash('sha256').update(otp).digest('hex');
      if (hashed !== otpData.otpHash) return res.status(400).json({ error: 'auth_otp_invalid' });

      await otpDoc.ref.update({ used: true });

      const usersSnap = await db.collection('users')
        .where('phone', 'in', [cleanPhone, `0${cleanPhone.slice(-9)}`, `+${cleanPhone}`])
        .limit(1)
        .get();

      if (usersSnap.empty) {
        return res.status(404).json({ error: 'auth_no_account' });
      }

      const uid = usersSnap.docs[0].id;

      try {
        await admin.auth().updateUser(uid, { password: newPassword });
      } catch (authErr) {
        return res.status(500).json({ error: 'failed_to_reset_password' });
      }

      res.json({ success: true, message: 'Nenosiri limebadilishwa kwa mafanikio.' });
    } catch (e) {
      console.error('/api/auth/reset-password-by-phone error:', e.message);
      res.status(500).json({ error: 'Internal server error' });
    }
  }

  async function phoneLogin(req, res) {
    try {
      const { phone, otp } = req.body;
      if (!phone || !otp) return res.status(400).json({ error: 'Phone and OTP are required' });
      if (!db) return res.status(503).json({ error: 'Database not configured' });

      const cleanPhone = phone.replace(/\D/g, '');

      const otpDoc = await db.collection('otp_codes').doc(cleanPhone).get();
      if (!otpDoc.exists) return res.status(400).json({ error: 'auth_otp_expired' });

      const otpData = otpDoc.data();
      if (otpData.used) return res.status(400).json({ error: 'auth_otp_invalid' });
      if (Date.now() > otpData.expiresAt) return res.status(400).json({ error: 'auth_otp_expired' });

      const hashed = crypto.createHash('sha256').update(otp).digest('hex');
      if (hashed !== otpData.otpHash) return res.status(400).json({ error: 'auth_otp_invalid' });

      await otpDoc.ref.update({ used: true });

      const usersSnap = await db.collection('users')
        .where('phone', 'in', [cleanPhone, `0${cleanPhone.slice(-9)}`, `+${cleanPhone}`])
        .limit(1)
        .get();

      let uid;
      if (usersSnap.empty) {
        const email = `phone_${cleanPhone}@soko-vibe.com`;
        const password = crypto.randomBytes(24).toString('base64url');
        const userRecord = await admin.auth().createUser({
          email,
          password,
          displayName: `User ${cleanPhone.slice(-4)}`,
        });
        uid = userRecord.uid;
        await db.collection('users').doc(uid).set({
          displayName: `User ${cleanPhone.slice(-4)}`,
          email,
          phone: cleanPhone,
          username: '',
          bio: '',
          location: '',
          mood: '',
          profileImage: '',
          paymentNumbers: {},
          shopBanner: '',
          shopBannerColor: '',
          shopAccentColor: '',
          latitude: null,
          longitude: null,
          coins: 0,
          viewerCoins: 0,
          sellerBalance: 0,
          soldCount: 0,
          isAdmin: false,
          isSuspended: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } else {
        uid = usersSnap.docs[0].id;
      }

      const token = await admin.auth().createCustomToken(uid);
      res.json({ success: true, token });
    } catch (e) {
      console.error('/api/phone-login error:', e.message);
      res.status(500).json({ error: 'Internal server error' });
    }
  }

  return { sendOtp, verifyOtp, sendEmailOtp, verifyEmailOtp, checkPhone, checkEmail, resetPasswordByPhone, phoneLogin };
};
