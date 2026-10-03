const crypto = require('crypto');
const { getFirebaseAuth } = require('../../config/firebase');
const { getStore } = require('../../config/database');
const { saveOtp, getOtp, markUsed, bumpAttempts, clearOtp, createOtpHash, verifyOtpHash } = require('../../services/otp-store');
const { sendMail } = require('../../services/mailer');
const { buildOtpEmail, buildPasswordChangedEmail } = require('../../services/email-templates');
const { deliverPhoneOtp } = require('../../services/otp-delivery');
const { releaseOtpClaim, checkTarget } = require('../../middleware/otpGuard');
const { clientIp } = require('../../middleware/rateLimiter');
const { writeAudit, auditFromReq } = require('../../services/audit');
const { maskPhone, maskEmail } = require('../../utils/pii');
const { validatePassword } = require('../../services/password-policy');
const { revokeUserSessions } = require('../../services/session-revocation');
const accountStore = require('../../services/account-store');

const OTP_TTL_SECONDS = 300; // 5 minutes
const OTP_MAX_ATTEMPTS = 5;

// Per-target ceiling for the pre-auth existence probes (stacked on top of the
// shared authLimiter IP bucket). Registration needs a duplicate check, but an
// open oracle must be expensive: 50 probes per target per 15 min, no cooldown.
const CHECK_MAX_PER_TARGET = parseInt(process.env.AUTH_CHECK_MAX_PER_TARGET || '50', 10);
const CHECK_WINDOW_MS = 15 * 60 * 1000;

// Fire-and-forget security audit for auth events. writeAudit swallows its own
// errors, so handlers stay one line each and auth never breaks because the
// audit table is slow. PII is masked: entityId carries channel + last digits
// only, never a full phone number or mailbox.
function authAudit(req, action, extra = {}) {
  try {
    const { inc } = require('../../services/auth-risk');
    inc(action);
  } catch (_) {}
  writeAudit({ ...auditFromReq(req), action, entityType: 'auth', ...extra });
}

// Probing tripwire for the existence oracles: many distinct targets from one
// IP inside the window is enumeration. Logged once per IP per window; the
// request itself is still served (per-target ceilings bound the damage).
async function probeCheck(req, target) {
  try {
    const { recordProbe } = require('../../services/auth-risk');
    const ip = clientIp(req);
    const { probing, distinct } = await recordProbe(ip, target);
    if (probing) {
      authAudit(req, 'auth_probing_detected', {
        entityId: `ip:${ip}`,
        newState: { distinctTargets: distinct },
      });
    }
  } catch (_) {}
}

function cleanPhone(phone) {
  return String(phone).replace(/\D/g, '');
}

// Send OTP to phone: generates a 6-digit code, stores its hash for 5
// minutes, then delivers it over the cheapest configured channel in order
// (push → SMS; see services/otp-delivery.js).
async function sendOtp(req, res) {
  try {
    const { phone } = req.body;
    const langCode = ['sw', 'en'].includes(req.body?.langCode) ? req.body.langCode : 'sw';
    const clean = cleanPhone(phone);
    const otp = crypto.randomInt(100000, 1000000).toString();

    await saveOtp(`phone:${clean}`, createOtpHash(otp), OTP_TTL_SECONDS);

    const message = langCode === 'en'
      ? `Your OTP is ${otp}. It expires in 5 minutes.`
      : `OTP yako ni ${otp}. Inaisha kwa dakika 5.`;

    const delivery = await deliverPhoneOtp({
      phone: clean,
      message,
      code: otp,
      langCode,
    });
    if (!delivery.delivered) {
      console.error('[AUTH] send-otp delivery failed for', maskPhone(clean));
      authAudit(req, 'otp_request_failed', { entityId: `phone:${maskPhone(clean)}` });
      // The code never reached the user. Both halves of the guard claim have to
      // go: the stored hash (so it cannot be verified later) AND the cooldown
      // plus quota slot the middleware already consumed. Rolling back only the
      // hash left the user waiting out a 60-second cooldown and one of just 3
      // quota slots for a message the backend failed to send.
      await clearOtp(`phone:${clean}`);
      await releaseOtpClaim(req);
      return res.status(502).json({ error: 'auth_otp_send_failed' });
    }

    authAudit(req, 'otp_requested', { entityId: `phone:${maskPhone(clean)}` });
    res.json({
      success: true,
      sent: true,
      channel: delivery.channel,
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
    if ((record.attempts || 0) >= OTP_MAX_ATTEMPTS) {
      authAudit(req, 'otp_verify_locked', { entityId: `phone:${maskPhone(clean)}` });
      return res.status(400).json({ error: 'auth_otp_invalid' });
    }

    // Attempts are bumped ONLY on a failed compare: bumping first let an
    // attacker burn a victim's budget with empty requests, and rejected a
    // correct code entered as the 6th attempt.
    if (!verifyOtpHash(otpValue, record.otpHash)) {
      const attempts = await bumpAttempts(`phone:${clean}`);
      authAudit(req, attempts >= OTP_MAX_ATTEMPTS ? 'otp_verify_locked' : 'otp_verify_failed', {
        entityId: `phone:${maskPhone(clean)}`,
      });
      return res.status(400).json({ error: 'auth_otp_invalid' });
    }

    await markUsed(`phone:${clean}`);
    authAudit(req, 'otp_verified', { entityId: `phone:${maskPhone(clean)}` });
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
      // Machine code, not a sentence: the app switches on `error`, and every
      // other auth route answers with a code like this.
      return res.status(400).json({ error: 'auth_invalid_email' });
    }
    const cleanEmail = email.trim().toLowerCase();
    const lang = ['sw', 'en'].includes(req.body?.langCode) ? req.body.langCode : 'sw';
    const otp = crypto.randomInt(100000, 1000000).toString();

    await saveOtp(`email:${cleanEmail}`, createOtpHash(otp), OTP_TTL_SECONDS);

    const { subject, html } = buildOtpEmail({
      otp,
      lang,
      expiresInMinutes: OTP_TTL_SECONDS / 60,
      recipientEmail: cleanEmail,
    });
    const sent = await sendMail(cleanEmail, subject, html);
    authAudit(req, sent ? 'otp_requested' : 'otp_request_failed', { entityId: `email:${maskEmail(cleanEmail)}` });
    if (!sent) {
      // The code never arrived (every channel failed, or the address bounced /
      // is suppressed). Drop the stored hash AND give back the cooldown and the
      // quota slot the guard already claimed, so the user can retry at once
      // instead of waiting on a 60s cooldown for a message that was never sent.
      await clearOtp(`email:${cleanEmail}`);
      await releaseOtpClaim(req);
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

// Shared email-OTP check: expiry, single-use, 5 attempts, timing-safe compare.
// Attempts bump only on a failed compare (see verifyOtp).
async function checkEmailCode(cleanEmail, otpValue) {
  if (!otpValue) return { ok: false, error: 'auth_otp_invalid' };
  const record = await getOtp(`email:${cleanEmail}`);
  if (!record || record.used || Date.now() > record.expiresAt) {
    return { ok: false, error: 'auth_otp_expired' };
  }
  if ((record.attempts || 0) >= OTP_MAX_ATTEMPTS) {
    return { ok: false, error: 'auth_otp_invalid', locked: true };
  }
  if (!verifyOtpHash(otpValue, record.otpHash)) {
    const attempts = await bumpAttempts(`email:${cleanEmail}`);
    return { ok: false, error: 'auth_otp_invalid', locked: attempts >= OTP_MAX_ATTEMPTS };
  }
  await markUsed(`email:${cleanEmail}`);
  return { ok: true };
}

// Flags the Firebase user's address as verified after an OTP check succeeded.
//
// Best-effort by design: the OTP proof has already been consumed and is
// authoritative, so a Firebase write failure must NOT turn a successful
// verification into an error the user sees and retries with a spent code. The
// flag is a convenience mirror for the app, not the source of truth — the OTP
// store is. Failures are logged loudly instead.
async function markFirebaseEmailVerified(cleanEmail) {
  try {
    const auth = getFirebaseAuth();
    if (!auth) {
      console.warn('[AUTH] Firebase not configured; skipping emailVerified flag for', maskEmail(cleanEmail));
      return false;
    }
    const user = await auth.getUserByEmail(cleanEmail);
    if (user.emailVerified) return true;
    await auth.updateUser(user.uid, { emailVerified: true });
    return true;
  } catch (err) {
    // NOT_FOUND here is expected: the address may have an OTP but no account
    // (a verification-before-registration flow), so it is not an error.
    const code = err && err.code ? String(err.code) : '';
    if (code === 'auth/user-not-found') return false;
    console.error('[AUTH] failed to set emailVerified for', maskEmail(cleanEmail), '-', err.message);
    return false;
  }
}

// Verify email OTP
async function verifyEmailOtp(req, res) {
  try {
    const { email, otp, code } = req.body;
    const otpValue = otp || code;
    if (!email || !otpValue) return res.status(400).json({ error: 'auth_otp_invalid' });
    const cleanEmail = String(email).trim().toLowerCase();

    const check = await checkEmailCode(cleanEmail, otpValue);
    if (!check.ok) return res.status(400).json({ error: check.error });

    // Prove the address in Firebase too. This handler used to answer
    // { valid: true } and nothing else, so a user who proved control of their
    // mailbox stayed emailVerified:false in Firebase forever: the app's
    // isEmailVerified() check (repositories/auth_repository.dart) kept reporting
    // "not verified", and any server-side policy that trusts that flag — or a
    // later `requireEmailVerified` — would reject a genuinely verified user.
    await markFirebaseEmailVerified(cleanEmail);

    res.json({
      success: true,
      valid: true,
    });
  } catch (error) {
    console.error('[AUTH] Verify email OTP error:', error.message);
    res.status(500).json({ error: 'Internal server error' });
  }
}

// Email + OTP login for the app: verifies the emailed code, resolves the
// Firebase user by email, returns a custom token the client signs in with.
//
// No account for the mailbox is NOT a 404: the OTP just proved the requester
// controls that mailbox, so the account is created (passwordless signup,
// mirroring phoneLogin auto-create). Besides better UX, this closes the
// account-enumeration oracle the 404 used to be.
async function emailOtpLogin(req, res) {
  try {
    const { email, otp, code } = req.body;
    const otpValue = otp || code;
    if (!email || !otpValue) return res.status(400).json({ error: 'auth_otp_invalid' });
    const cleanEmail = String(email).trim().toLowerCase();
    const check = await checkEmailCode(cleanEmail, otpValue);
    if (!check.ok) {
      authAudit(req, check.locked ? 'otp_verify_locked' : 'otp_verify_failed', {
        entityId: `email:${maskEmail(cleanEmail)}`,
      });
      return res.status(400).json({ error: check.error });
    }

    const auth = getFirebaseAuth();
    if (!auth) return res.status(503).json({ error: 'Auth not configured' });

    let uid;
    let created = false;
    try {
      const record = await auth.getUserByEmail(cleanEmail);
      uid = record.uid;
    } catch (e) {
      const userRecord = await auth.createUser({
        email: cleanEmail,
        emailVerified: true,
        password: crypto.randomBytes(24).toString('base64url'),
        displayName: cleanEmail.split('@')[0],
      });
      uid = userRecord.uid;
      created = true;
      const store = getStore();
      await store.user.create({
        data: {
          firebaseUid: uid,
          email: cleanEmail,
          displayName: cleanEmail.split('@')[0],
          accountStatus: 'active',
          lastLoginAt: new Date(),
        },
      });
      await accountStore.writeProfile(uid, {
        col: {
          email: cleanEmail,
          displayName: cleanEmail.split('@')[0],
          preferredLanguage: 'sw',
          accountStatus: 'active',
          createdAt: new Date().toISOString(),
        },
        meta: { lastActive: new Date().toISOString(), profile: {} },
      });
    }

    const token = await auth.createCustomToken(uid);
    authAudit(req, 'email_otp_login', {
      actorId: uid,
      actorType: 'user',
      entityId: `email:${maskEmail(cleanEmail)}`,
      newState: created ? { createdViaOtp: true } : undefined,
    });
    res.json({ success: true, token, created });
  } catch (error) {
    console.error('[AUTH] Email OTP login error:', error.message);
    res.status(500).json({ error: 'Internal server error' });
  }
}

// Admin OTP sign-in: the emailed code must verify AND the account must carry
// an admin role — guards the dashboard against non-admin OTP signups.
async function otpSignIn(req, res) {
  try {
    const { email, otp, code } = req.body;
    const otpValue = otp || code;
    if (!email || !otpValue) return res.status(400).json({ error: 'auth_otp_invalid' });
    const cleanEmail = String(email).trim().toLowerCase();
    const check = await checkEmailCode(cleanEmail, otpValue);
    if (!check.ok) return res.status(400).json({ error: check.error });

    const auth = getFirebaseAuth();
    if (!auth) return res.status(503).json({ error: 'Auth not configured' });

    // Missing account and non-admin resolve to the SAME 403: distinguishing
    // them would let anyone probe which mailboxes belong to admins.
    let uid = null;
    let isAdmin = false;
    try {
      const record = await auth.getUserByEmail(cleanEmail);
      uid = record.uid;
      const store = getStore();
      const user = await store.user.findFirst({
        where: { firebaseUid: uid },
        select: { role: true },
      });
      if (user && ['admin', 'super_admin'].includes(user.role)) {
        isAdmin = true;
      } else {
        // Firestore users/{uid}.role is authoritative for admin identity once the
        // account has no seam row (fresh-backed admin bookings).
        const doc = await accountStore.getProfile(uid);
        if (doc && ['admin', 'super_admin'].includes(doc.role)) isAdmin = true;
      }
    } catch (e) {
      uid = null;
    }
    if (!isAdmin || !uid) {
      authAudit(req, 'admin_otp_signin_denied', { entityId: `email:${maskEmail(cleanEmail)}` });
      return res.status(403).json({ error: 'ADMIN_REQUIRED' });
    }

    const customToken = await auth.createCustomToken(uid);
    authAudit(req, 'admin_otp_signin', { actorId: uid, actorType: 'user' });
    res.json({ customToken, uid });
  } catch (error) {
    console.error('[AUTH] Admin OTP sign-in error:', error.message);
    res.status(500).json({ error: 'Internal server error' });
  }
}

// Check if phone exists — Firestore users/{uid} is authoritative; Postgres
// is a fallback for legacy accounts that predate the Firestore records.
async function checkPhone(req, res) {
  try {
    const { phone } = req.body;

    if (!phone) {
      return res.status(400).json({ error: 'Phone number required' });
    }

    const clean = cleanPhone(phone);
    // Registration needs this probe, but an open oracle must be expensive:
    // per-target ceiling stacked on the shared authLimiter IP bucket.
    const throttle = await checkTarget(`check:phone:${clean}`, clientIp(req), {
      cooldown: false,
      maxPerKey: CHECK_MAX_PER_TARGET,
    }).catch(() => ({ ok: true }));
    if (!throttle.ok) {
      authAudit(req, 'account_probe_throttled', { entityId: `phone:${maskPhone(clean)}` });
      res.setHeader('Retry-After', String(Math.max(1, Math.ceil(CHECK_WINDOW_MS / 1000))));
      return res.status(429).json({ error: 'auth_otp_limit', success: false });
    }
    await probeCheck(req, `phone:${clean}`);
    const fs = await accountStore.byPhoneFirestore(clean);
    if (fs) return res.json({ exists: true });

    const store = getStore();
    const user = await store.user.findFirst({
      where: { OR: phoneVariants(clean).map((p) => ({ phone: p })) },
      select: { id: true },
    });

    res.json({ exists: !!user });
  } catch (error) {
    console.error('[AUTH] Check phone error:', error.message);
    res.status(500).json({ error: 'Failed to check phone' });
  }
}

// Check if email exists — Firestore users/{uid} is authoritative; Postgres
// is a fallback for legacy accounts that predate the Firestore records.
async function checkEmail(req, res) {
  try {
    const { email } = req.body;

    if (!email) {
      return res.status(400).json({ error: 'Email required' });
    }

    const cleanEmail = String(email).trim().toLowerCase();
    const throttle = await checkTarget(`check:email:${cleanEmail}`, clientIp(req), {
      cooldown: false,
      maxPerKey: CHECK_MAX_PER_TARGET,
    }).catch(() => ({ ok: true }));
    if (!throttle.ok) {
      authAudit(req, 'account_probe_throttled', { entityId: `email:${maskEmail(cleanEmail)}` });
      res.setHeader('Retry-After', String(Math.max(1, Math.ceil(CHECK_WINDOW_MS / 1000))));
      return res.status(429).json({ error: 'auth_otp_limit', success: false });
    }
    await probeCheck(req, `email:${cleanEmail}`);
    const fs = await accountStore.byEmailFirestore(cleanEmail);
    if (fs) return res.json({ exists: true });

    const store = getStore();
    const user = await store.user.findUnique({
      where: { email: cleanEmail },
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
// Attempts bump only on a failed compare (see verifyOtp).
// Returns { ok: true } or { ok: false, error, locked }.
async function checkPhoneCode(clean, otpValue) {
  if (!otpValue) return { ok: false, error: 'auth_otp_invalid' };
  const record = await getOtp(`phone:${clean}`);
  if (!record || record.used || Date.now() > record.expiresAt) {
    return { ok: false, error: 'auth_otp_expired' };
  }
  if ((record.attempts || 0) >= OTP_MAX_ATTEMPTS) {
    return { ok: false, error: 'auth_otp_invalid', locked: true };
  }
  if (!verifyOtpHash(otpValue, record.otpHash)) {
    const attempts = await bumpAttempts(`phone:${clean}`);
    return { ok: false, error: 'auth_otp_invalid', locked: attempts >= OTP_MAX_ATTEMPTS };
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
    if (!check.ok) {
      authAudit(req, check.locked ? 'otp_verify_locked' : 'otp_verify_failed', {
        entityId: `phone:${maskPhone(clean)}`,
      });
      return res.status(400).json({ error: check.error });
    }

    const auth = getFirebaseAuth();
    if (!auth) return res.status(503).json({ error: 'Auth not configured' });
    const store = getStore();

    let user = await store.user.findFirst({
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
      await store.user.create({
        data: {
          firebaseUid: uid,
          phone: clean,
          email,
          displayName: `User ${clean.slice(-4)}`,
          phoneVerified: true,
          accountStatus: 'active',
          lastLoginAt: new Date(),
        },
      });
      // Firestore users/{uid} is the authoritative app profile; seed it so
      // /me, public profiles, and phone/email checks read Firestore first.
      await accountStore.writeProfile(uid, {
        col: {
          phone: clean,
          email,
          displayName: `User ${clean.slice(-4)}`,
          preferredLanguage: 'sw',
          phoneVerified: true,
          accountStatus: 'active',
          createdAt: new Date().toISOString(),
        },
        meta: { lastActive: new Date().toISOString(), profile: {} },
      });
    } else {
      uid = user.firebaseUid;
      await store.user.update({
        where: { id: user.id },
        data: { lastLoginAt: new Date(), phoneVerified: true, accountStatus: 'active' },
      }).catch(() => {});

      // Lazy-migrate old accounts: create the Firestore doc on first login so
      // the full user base reaches Firestore-primary without a bulk backfill.
      const doc = await accountStore.getProfile(uid);
      if (!doc) {
        const row = await store.user.findUnique({
          where: { id: user.id },
          select: {
            displayName: true, username: true, phone: true, email: true,
            preferredLanguage: true, avatarUrl: true, accountStatus: true,
            createdAt: true, metadata: true,
          },
        });
        if (row) {
          await accountStore.writeProfile(uid, {
            col: {
              phone: row.phone || null,
              email: row.email || null,
              displayName: row.displayName || null,
              username: row.username || null,
              avatarUrl: row.avatarUrl || null,
              preferredLanguage: row.preferredLanguage || 'sw',
              phoneVerified: true,
              accountStatus: row.accountStatus || 'active',
              createdAt: row.createdAt ? row.createdAt.toISOString() : new Date().toISOString(),
            },
            meta: {
              lastActive: new Date().toISOString(),
              profile: (row.metadata && row.metadata.profile) || {},
            },
          });
        }
      }
    }

    const token = await auth.createCustomToken(uid);
    authAudit(req, 'phone_otp_login', {
      actorId: uid,
      actorType: 'user',
      entityId: `phone:${maskPhone(clean)}`,
    });
    res.json({ success: true, token });
  } catch (error) {
    console.error('[AUTH] Phone login error:', error.message);
    res.status(500).json({ error: 'Internal server error' });
  }
}

// Reset password by phone + OTP (for phone-registered accounts).
//
// The response is identical whether or not an account exists for the phone:
// the OTP already proved control of the number, so a 404 here would be a
// pure account-enumeration oracle with no UX value.
async function resetPasswordByPhone(req, res) {
  try {
    const { phone, otp, code, newPassword } = req.body;
    if (!phone || !(otp || code) || !newPassword) {
      return res.status(400).json({ error: 'Phone, OTP, and new password are required' });
    }
    const policy = validatePassword(newPassword);
    if (!policy.ok) {
      return res.status(400).json({ error: policy.code });
    }
    const clean = cleanPhone(phone);
    const check = await checkPhoneCode(clean, otp || code);
    if (!check.ok) {
      authAudit(req, check.locked ? 'otp_verify_locked' : 'otp_verify_failed', {
        entityId: `phone:${maskPhone(clean)}`,
      });
      return res.status(400).json({ error: check.error });
    }

    const auth = getFirebaseAuth();
    if (!auth) return res.status(503).json({ error: 'Auth not configured' });
    const store = getStore();

    const user = await store.user.findFirst({
      where: { OR: phoneVariants(clean).map((p) => ({ phone: p })) },
      select: { firebaseUid: true },
    });

    let uid = user?.firebaseUid || null;
    if (!uid) {
      try {
        const existing = await auth.getUserByEmail(syntheticEmail(clean));
        uid = existing.uid;
      } catch (_) {
        uid = null;
      }
    }

    if (uid) {
      try {
        await auth.updateUser(uid, { password: String(newPassword) });
      } catch (authErr) {
        authAudit(req, 'password_reset_failed', { actorId: uid, actorType: 'user' });
        return res.status(500).json({ error: 'failed_to_reset_password' });
      }
      // Recovery invalidates every old session: a password reset means the
      // previous credential is compromised until proven otherwise.
      await revokeUserSessions(uid).catch(() => null);
      authAudit(req, 'password_changed', { actorId: uid, actorType: 'user' });
      // Best-effort security mail to the account's mailbox, if it has a real
      // one (synthetic phone_* addresses receive nothing — no mailbox).
      // Queued, never awaited: the reset answer must not wait on SMTP.
      try {
        const record = await auth.getUser(uid);
        const mailbox = record.email && !record.email.startsWith('phone_') ? record.email : null;
        if (mailbox) {
          const lang = ['sw', 'en'].includes(req.body?.langCode) ? req.body.langCode : 'sw';
          const { subject, html } = buildPasswordChangedEmail({
            lang,
            when: new Date().toISOString(),
          });
          const { enqueueNotification } = require('../../services/notification-worker');
          await enqueueNotification('email', { to: mailbox, subject, html }, {
            idempotencyKey: `pwd-changed:${uid}:${Date.now()}`,
          });
        }
      } catch (_) {
        // Notification failure must never fail the reset itself.
      }
    } else {
      authAudit(req, 'password_reset_no_account', { entityId: `phone:${maskPhone(clean)}` });
    }

    res.json({ success: true, message: 'Nenosiri limebadilishwa kwa mafanikio.' });
  } catch (error) {
    console.error('[AUTH] Reset password error:', error.message);
    res.status(500).json({ error: 'Internal server error' });
  }
}

// Logout from all devices: stamps sessionRevokedAt so every token minted
// before now dies on routes enforcing requireFreshSession (money, admin,
// auth-sensitive). The client signs out locally right after this returns.
// "Logout current device" stays a local FirebaseAuth.signOut — per-device
// revocation is impossible with bearer ID tokens.
async function logoutAll(req, res) {
  try {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: 'AUTH_REQUIRED' });
    const stamped = await revokeUserSessions(uid);
    if (!stamped) return res.status(503).json({ error: 'Auth not configured' });
    authAudit(req, 'logout_all_devices', { actorId: uid, actorType: 'user' });
    res.json({ success: true });
  } catch (error) {
    console.error('[AUTH] Logout-all error:', error.message);
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
  emailOtpLogin,
  otpSignIn,
  logoutAll,
};
