// Legacy auth helpers for compat-mounted old routers.
// Mirrors the old server semantics: Firebase Bearer -> uid; admin via
// x-admin-secret or Firestore isAdmin flag.
const { getFirebaseAuth } = require('../../config/firebase');
const { getFirebaseFirestore } = require('../../config/firebase');
const config = require('../../config');

function db() {
  return getFirebaseFirestore();
}

function deny(res, status, error) {
  if (res) res.status(status).json({ error });
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
    return { ok: true, uid: decoded.uid };
  } catch (_) {
    return deny(res, 403, 'Invalid token');
  }
}

async function requireAdmin(req, res) {
  const secret = req.headers['x-admin-secret'];
  if (secret && config.security.adminSecret && secret === config.security.adminSecret) {
    return { ok: true, uid: 'admin-secret' };
  }
  const authHeader = req.headers['authorization'] || req.headers['Authorization'] || '';
  if (authHeader.startsWith('Bearer ')) {
    try {
      const auth = getFirebaseAuth();
      const store = db();
      if (auth && store) {
        const decoded = await auth.verifyIdToken(authHeader.slice(7));
        const userDoc = await store.collection('users').doc(decoded.uid).get();
        if (userDoc.exists && userDoc.data().isAdmin === true) {
          return { ok: true, uid: decoded.uid };
        }
      }
    } catch (_) {}
  }
  if (res) res.status(401).json({ error: 'Unauthorized' });
  return { ok: false };
}

async function isOwnerOrAdmin(req, res, ownerId) {
  const auth = await requireUser(req, res);
  if (!auth.ok) return false;
  if (auth.uid === ownerId) return true;
  const adminAuth = await requireAdmin(req, res);
  return adminAuth.ok;
}

async function checkSuspended(userId) {
  const store = db();
  if (!store) return false;
  try {
    const userDoc = await store.collection('users').doc(userId).get();
    if (!userDoc.exists) return false;
    return userDoc.data().isSuspended === true;
  } catch {
    return false;
  }
}

module.exports = { requireUser, requireAdmin, isOwnerOrAdmin, checkSuspended };
