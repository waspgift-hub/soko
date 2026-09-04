const crypto = require('crypto');
const { getFirebaseAuth } = require('../../config/firebase');
const { getPrisma } = require('../../config/database');
const { sendSms } = require('../../services/sms-service');
const { saveOtp, getOtp, markUsed, bumpAttempts } = require('../../services/otp-store');
const { sendMail } = require('../../services/mailer');

const OTP_TTL_SECONDS = 300; // 5 minutes
const OTP_MAX_ATTEMPTS = 5;

function hashOtp(value) {
  return crypto.createHash('sha256').update(String(value)).digest('hex');
}

function cleanPhone(phone) {
  return String(phone).replace(/\D/g, '');
}

// Send OTP to phone: generates a 6-digit code, stores its hash for 5
// minutes, and delivers it by SMS (Meseji, Notify Africa fallback).
async function sendOtp(req, res) {
  try {
    const { phone } = req.body;
    const langCode = ['sw', 'en', 'zh'].includes(req.body?.langCode) ? req.body.langCode : 'sw';
    const clean = cleanPhone(phone);
    const otp = crypto.randomInt(100000, 1000000).toString();

    await saveOtp(`phone:${clean}`, hashOtp(otp), OTP_TTL_SECONDS);

    const message = langCode === 'en'
      ? `Your OTP is ${otp}. It expires in 5 minutes.`
      : langCode === 'zh'
        ? `您的验证码是${otp}，5分钟内有效。`
        : `OTP yako ni ${otp}. Inaisha kwa dakika 5.`;
    const sent = await sendSms(clean, message);
    if (!sent) {
      console.error('[AUTH] send-otp SMS failed for', clean);
      return res.status(502).json({ error: 'auth_otp_send_failed' });
    }

    res.json({
      success: true,
      sent: true,
      message: 'OTP imetumwa kwa simu yako',
    });
  } catch (error) {
    console.error('[AUTH] Send OTP error:', error.message);
    res.status(500).json({ error: 'auth_otp_send_failed' });
  }
}

// Verify phone OTP: timing-safe hash compare, single-use, 5 attempts max.
async function verifyOtp(req, res) {
  try {
    const { phone, otp, code } = req.body;
    const otpValue = otp || code;
    if (!otpValue) return res.status(400).json({ error: 'auth_otp_invalid' });
    const clean = cleanPhone(phone);

    const record = await getOtp(`phone:${clean}`);
    if (!record || record.used || Date.now() > record.expiresAt) {
      return res.status(400).json({ error: 'auth_otp_expired' });
    }

    const attempts = await bumpAttempts(`phone:${clean}`);
    if (attempts > OTP_MAX_ATTEMPTS) {
      return res.status(400).json({ error: 'auth_otp_invalid' });
    }

    const hashed = hashOtp(otpValue);
    const a = Buffer.from(hashed);
    const b = Buffer.from(record.otpHash);
    if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
      return res.status(400).json({ error: 'auth_otp_invalid' });
    }

    await markUsed(`phone:${clean}`);
    res.json({
      success: true,
      valid: true,
    });
  } catch (error) {
    console.error('[AUTH] Verify OTP error:', error.message);
    res.status(500).json({ error: 'Internal server error' });
  }
}

// Send email OTP: same storage rules, delivered by SMTP.
async function sendEmailOtp(req, res) {
  try {
    const { email } = req.body;

    if (!email || !email.includes('@')) {
      return res.status(400).json({ error: 'Valid email required' });
    }
    const cleanEmail = email.trim().toLowerCase();
    const lang = ['sw', 'en', 'zh'].includes(req.body?.langCode) ? req.body.langCode : 'sw';
    const otp = crypto.randomInt(100000, 1000000).toString();

    await saveOtp(`email:${cleanEmail}`, hashOtp(otp), OTP_TTL_SECONDS);

    const subject = lang === 'en' ? 'Your login code' : lang === 'zh' ? '您的登录验证码' : 'Namba yako ya kuingia';
    const html = `<html><body style="font-family:Arial,sans-serif;padding:20px;max-width:600px;margin:0 auto"><h2 style="color:#40916C">Soko Vibe</h2><p style="font-size:32px;font-weight:bold;letter-spacing:8px;color:#40916C">${otp}</p><p>${lang === 'en' ? 'Expires in 5 minutes.' : lang === 'zh' ? '5分钟内有效。' : 'Inaisha kwa dakika 5.'}</p></body></html>`;
    const sent = await sendMail(cleanEmail, subject, html);
    if (!sent) {
      return res.status(502).json({ error: 'auth_otp_send_failed' });
    }

    res.json({
      success: true,
      sent: true,
      message: 'OTP imetumwa kwa barua pepe yako',
    });
  } catch (error) {
    console.error('[AUTH] Send email OTP error:', error.message);
    res.status(500).json({ error: 'auth_otp_send_failed' });
  }
}

// Verify email OTP
async function verifyEmailOtp(req, res) {
  try {
    const { email, otp, code } = req.body;
    const otpValue = otp || code;
    if (!email || !otpValue) return res.status(400).json({ error: 'auth_otp_invalid' });
    const cleanEmail = String(email).trim().toLowerCase();

    const record = await getOtp(`email:${cleanEmail}`);
    if (!record || record.used || Date.now() > record.expiresAt) {
      return res.status(400).json({ error: 'auth_otp_expired' });
    }

    const attempts = await bumpAttempts(`email:${cleanEmail}`);
    if (attempts > OTP_MAX_ATTEMPTS) {
      return res.status(400).json({ error: 'auth_otp_invalid' });
    }

    const hashed = hashOtp(otpValue);
    const a = Buffer.from(hashed);
    const b = Buffer.from(record.otpHash);
    if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
      return res.status(400).json({ error: 'auth_otp_invalid' });
    }

    await markUsed(`email:${cleanEmail}`);
    res.json({
      success: true,
      valid: true,
    });
  } catch (error) {
    console.error('[AUTH] Verify email OTP error:', error.message);
    res.status(500).json({ error: 'Internal server error' });
  }
}

// Check if phone exists
async function checkPhone(req, res) {
  try {
    const { phone } = req.body;
    
    if (!phone) {
      return res.status(400).json({ error: 'Phone number required' });
    }

    const prisma = getPrisma();
    const user = await prisma.user.findUnique({
      where: { phone },
      select: { id: true },
    });

    res.json({ exists: !!user });
  } catch (error) {
    console.error('[AUTH] Check phone error:', error.message);
    res.status(500).json({ error: 'Failed to check phone' });
  }
}

// Check if email exists
async function checkEmail(req, res) {
  try {
    const { email } = req.body;
    
    if (!email) {
      return res.status(400).json({ error: 'Email required' });
    }

    const prisma = getPrisma();
    const user = await prisma.user.findUnique({
      where: { email },
      select: { id: true },
    });

    res.json({ exists: !!user });
  } catch (error) {
    console.error('[AUTH] Check email error:', error.message);
    res.status(500).json({ error: 'Failed to check email' });
  }
}

// Phone number variants stored across clients (0..., +255..., 255...).
function phoneVariants(clean) {
  const last9 = clean.slice(-9);
  return [...new Set([clean, `0${last9}`, `+${clean}`])];
}

function syntheticEmail(clean) {
  return `phone_${clean}@soko-vibe.com`;
}

// Shared phone-OTP check: expiry, single-use, 5 attempts, timing-safe.
// Returns { ok: true } or { ok: false, error }.
async function checkPhoneCode(clean, otpValue) {
  if (!otpValue) return { ok: false, error: 'auth_otp_invalid' };
  const record = await getOtp(`phone:${clean}`);
  if (!record || record.used || Date.now() > record.expiresAt) {
    return { ok: false, error: 'auth_otp_expired' };
  }
  const attempts = await bumpAttempts(`phone:${clean}`);
  if (attempts > OTP_MAX_ATTEMPTS) {
    return { ok: false, error: 'auth_otp_invalid' };
  }
  const hashed = hashOtp(otpValue);
  const a = Buffer.from(hashed);
  const b = Buffer.from(record.otpHash);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
    return { ok: false, error: 'auth_otp_invalid' };
  }
  await markUsed(`phone:${clean}`);
  return { ok: true };
}

// Phone login: verifies OTP, finds or creates the Firebase user, and
// returns a Firebase custom token the app signs in with.
async function phoneLogin(req, res) {
  try {
    const { phone, otp, code } = req.body;
    if (!phone || !(otp || code)) {
      return res.status(400).json({ error: 'Phone and OTP are required' });
    }
    const clean = cleanPhone(phone);
    const check = await checkPhoneCode(clean, otp || code);
    if (!check.ok) return res.status(400).json({ error: check.error });

    const auth = getFirebaseAuth();
    if (!auth) return res.status(503).json({ error: 'Auth not configured' });
    const prisma = getPrisma();

    let user = await prisma.user.findFirst({
      where: { OR: phoneVariants(clean).map((p) => ({ phone: p })) },
      select: { id: true, firebaseUid: true },
    });

    let uid;
    if (!user) {
      const email = syntheticEmail(clean);
      const password = crypto.randomBytes(24).toString('base64url');
      const userRecord = await auth.createUser({
        email,
        password,
        displayName: `User ${clean.slice(-4)}`,
      });
      uid = userRecord.uid;
      await prisma.user.create({
        data: {
          firebaseUid: uid,
          phone: clean,
          email,
          displayName: `User ${clean.slice(-4)}`,
          phoneVerified: true,
          lastLoginAt: new Date(),
        },
      });
    } else {
      uid = user.firebaseUid;
      await prisma.user.update({
        where: { id: user.id },
        data: { lastLoginAt: new Date(), phoneVerified: true },
      }).catch(() => {});
    }

    const token = await auth.createCustomToken(uid);
    res.json({ success: true, token });
  } catch (error) {
    console.error('[AUTH] Phone login error:', error.message);
    res.status(500).json({ error: 'Internal server error' });
  }
}

// Reset password by phone + OTP (for phone-registered accounts).
async function resetPasswordByPhone(req, res) {
  try {
    const { phone, otp, code, newPassword } = req.body;
    if (!phone || !(otp || code) || !newPassword) {
      return res.status(400).json({ error: 'Phone, OTP, and new password are required' });
    }
    if (String(newPassword).length < 8) {
      return res.status(400).json({ error: 'Password must be at least 8 characters' });
    }
    const clean = cleanPhone(phone);
    const check = await checkPhoneCode(clean, otp || code);
    if (!check.ok) return res.status(400).json({ error: check.error });

    const auth = getFirebaseAuth();
    if (!auth) return res.status(503).json({ error: 'Auth not configured' });
    const prisma = getPrisma();

    const user = await prisma.user.findFirst({
      where: { OR: phoneVariants(clean).map((p) => ({ phone: p })) },
      select: { firebaseUid: true },
    });

    let uid = user?.firebaseUid || null;
    if (!uid) {
      try {
        const existing = await auth.getUserByEmail(syntheticEmail(clean));
        uid = existing.uid;
      } catch (_) {
        return res.status(404).json({ error: 'auth_no_account' });
      }
    }

    try {
      await auth.updateUser(uid, { password: String(newPassword) });
    } catch (authErr) {
      return res.status(500).json({ error: 'failed_to_reset_password' });
    }

    res.json({ success: true, message: 'Nenosiri limebadilishwa kwa mafanikio.' });
  } catch (error) {
    console.error('[AUTH] Reset password error:', error.message);
    res.status(500).json({ error: 'Internal server error' });
  }
}

module.exports = {
  sendOtp,
  verifyOtp,
  sendEmailOtp,
  verifyEmailOtp,
  checkPhone,
  checkEmail,
  phoneLogin,
  resetPasswordByPhone,
};
