const { verifyAdminSecret } = require('./security');

const otpPhoneHits = new Map();
const OTP_PHONE_WINDOW = 15 * 60 * 1000;
const OTP_PHONE_MAX = 3;

const otpVerifyHits = new Map();
const OTP_VERIFY_WINDOW = 15 * 60 * 1000;
const OTP_VERIFY_MAX = 5;

setInterval(() => {
  const now = Date.now();
  for (const map of [otpPhoneHits, otpVerifyHits]) {
    for (const [key, times] of map) {
      const live = times.filter((t) => now - t < OTP_PHONE_WINDOW);
      if (live.length === 0) map.delete(key);
      else map.set(key, live);
    }
  }
}, 5 * 60 * 1000).unref();

module.exports = function ({ admin, db }) {
  function otpPhoneRateLimit(req, res, next) {
    const phone = (req.body?.phone || '').replace(/\D/g, '');
    if (!phone) return next();
    const now = Date.now();
    if (!otpPhoneHits.has(phone)) otpPhoneHits.set(phone, []);
    const hits = otpPhoneHits.get(phone).filter(t => now - t < OTP_PHONE_WINDOW);
    hits.push(now);
    otpPhoneHits.set(phone, hits);
    if (hits.length > OTP_PHONE_MAX) {
      return res.status(429).json({ error: 'auth_otp_rate_limited' });
    }
    next();
  }

  function otpVerifyRateLimit(req, res, next) {
    const phone = (req.body?.phone || '').replace(/\D/g, '');
    const key = phone || (req.body?.email || '').trim().toLowerCase();
    if (!key) return next();
    const now = Date.now();
    if (!otpVerifyHits.has(key)) otpVerifyHits.set(key, []);
    const hits = otpVerifyHits.get(key).filter(t => now - t < OTP_VERIFY_WINDOW);
    hits.push(now);
    otpVerifyHits.set(key, hits);
    if (hits.length > OTP_VERIFY_MAX) {
      return res.status(429).json({ error: 'auth_otp_rate_limited' });
    }
    next();
  }

  async function requireUser(req, res) {
    const authHeader = req.headers['authorization'] || req.headers['Authorization'] || '';
    if (!authHeader.startsWith('Bearer ')) {
      res.status(401).json({ error: 'Unauthorized' });
      return { ok: false };
    }
    try {
      const decoded = await admin.auth().verifyIdToken(authHeader.slice(7));
      return { ok: true, uid: decoded.uid };
    } catch (_) {
      res.status(403).json({ error: 'Invalid token' });
      return { ok: false };
    }
  }

  async function requireAdmin(req, res) {
    const secret = req.headers['x-admin-secret'];
    if (verifyAdminSecret(secret)) {
      return { ok: true, uid: 'admin-secret' };
    }
    const authHeader = req.headers['authorization'] || req.headers['Authorization'] || '';
    if (authHeader.startsWith('Bearer ')) {
      try {
        const decoded = await admin.auth().verifyIdToken(authHeader.slice(7));
        if (db) {
          const userDoc = await db.collection('users').doc(decoded.uid).get();
          if (userDoc.exists && userDoc.data().isAdmin === true) {
            return { ok: true, uid: decoded.uid };
          }
        }
      } catch (_) {}
    }
    res.status(401).json({ error: 'Unauthorized' });
    return { ok: false };
  }

  async function isOwnerOrAdmin(req, res, ownerId) {
    const auth = await requireUser(req, res);
    if (!auth.ok) return false;
    if (auth.uid === ownerId) return true;
    const adminAuth = await requireAdmin(req, res);
    return adminAuth.ok;
  }

  return { otpPhoneRateLimit, otpVerifyRateLimit, requireUser, requireAdmin, isOwnerOrAdmin };
};
