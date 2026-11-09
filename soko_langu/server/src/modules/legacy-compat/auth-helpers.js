// Legacy auth helpers for compat-mounted old routers.
// Mirrors the old server semantics: Firebase Bearer -> uid; admin via
// x-admin-secret or Firestore isAdmin flag.
const { getFirebaseAuth } = require('../../config/firebase');
const commerceStore = require('../../services/commerce-store');
const config = require('../../config');
const totp = require('../../services/totp');
const crypto = require('crypto');

function isBootstrapSuperAdminEmail(email) {
  if (!email) return false;
  const list = config.security && config.security.superAdminEmails;
  return Array.isArray(list) && list.includes(String(email).trim().toLowerCase());
}

function decryptSecret(blob) {
  const raw = Buffer.from(String(blob), 'base64');
  const iv = raw.slice(0, 12);
  const tag = raw.slice(12, 28);
  const enc = raw.slice(28);
  const key = crypto.createHash('sha256').update(String(process.env.ENCRYPTION_KEY || process.env.ADMIN_SECRET || 'soko-vibe')).digest();
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(enc), decipher.final()]).toString('utf8');
}

// Deleted the db() helper function

function deny(res, status, error) {
  if (res && !res.headersSent) res.status(status).json({ error });
  return { ok: false };
}

async function requireUser(req, res) {
  const authHeader = req.headers['authorization'] || req.headers['Authorization'] || '';
  if (!authHeader.startsWith('Bearer ')) {
    return deny(res, 401, 'Unauthorized');
  }
  try {
    const auth = getFirebaseAuth();
    if (!auth) {
      return deny(res, 503, 'Auth not configured');
    }
    const decoded = await auth.verifyIdToken(authHeader.slice(7));
    // Logout-all enforcement for legacy routes: tokens minted before the
    // user's revocation stamp die here, same as requireActive on v1 money
    // routes. Fail-open on store outage (token already verified).
    try {
      const { isSessionRevoked } = require('../../services/session-revocation');
      if (await isSessionRevoked(decoded.uid, decoded.auth_time)) {
        return deny(res, 401, 'SESSION_REVOKED');
      }
    } catch (e) {
      console.error('[AUTH] legacy revocation check failed:', e.message);
    }
    return { ok: true, uid: decoded.uid };
  } catch (_) {
    return deny(res, 403, 'Invalid token');
  }
}

async function requireAdmin(req, res) {
  let auth = null;
  const secret = req.headers['x-admin-secret'];
  if (secret && config.security.adminSecret && secret === config.security.adminSecret) {
    auth = { ok: true, uid: 'admin-secret' };
  } else {
    const authHeader = req.headers['authorization'] || req.headers['Authorization'] || '';
    if (authHeader.startsWith('Bearer ')) {
      try {
        const a = getFirebaseAuth();
        if (a) {
          const decoded = await a.verifyIdToken(authHeader.slice(7));
          const userDoc = await commerceStore.getDocument('users', decoded.uid);
          const roleOk = userDoc && ['admin', 'super_admin'].includes(userDoc.role);
          if (userDoc && (userDoc.isAdmin === true || roleOk || isBootstrapSuperAdminEmail(userDoc.email))) {
            auth = { ok: true, uid: decoded.uid };
          }
        }
      } catch (_) {}
    }
  }
  if (!auth) {
    if (res && !res.headersSent) res.status(401).json({ error: 'Unauthorized' });
    return { ok: false };
  }
  // MFA (TOTP) enforcement: if the admin has enrolled MFA, require a valid
  // code on every request (header x-admin-totp). Fail closed.
  try {
    const userDoc = await commerceStore.getDocument('users', auth.uid);
    const mfa = userDoc && userDoc.mfa;
    if (mfa && mfa.enabled && mfa.secret) {
      const code = req.headers['x-admin-totp'];
      let sec;
      try { sec = decryptSecret(mfa.secret); } catch (_) { sec = null; }
      if (!sec || !totp.verify(sec, code)) {
        if (res && !res.headersSent) res.status(401).json({ error: 'MFA_REQUIRED' });
        return { ok: false };
      }
    }
  } catch (_) { /* fail open on store error to avoid lockout */ }
  return auth;
}

async function isOwnerOrAdmin(req, res, ownerId) {
  const auth = await requireUser(req, res);
  if (!auth.ok) return false;
  if (auth.uid === ownerId) return true;
  const adminAuth = await requireAdmin(req, res);
  return adminAuth.ok;
}

async function checkSuspended(userId) {
  try {
    const userDoc = await commerceStore.getDocument('users', userId);
    if (!userDoc) return false;
    return userDoc.isSuspended === true;
  } catch {
    return false;
  }
}

module.exports = { requireUser, requireAdmin, isOwnerOrAdmin, checkSuspended };
