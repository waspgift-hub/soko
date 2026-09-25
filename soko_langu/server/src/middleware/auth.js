const crypto = require('crypto');
const { getFirebaseAuth } = require('../config/firebase');
const { getPrisma } = require('../config/database');
const { recordUserActivity } = require('../services/activity');
const config = require('../config');

// Verify Firebase ID token and attach user to request
async function authenticate(req, res, next) {
  const authHeader = req.headers.authorization || '';
  
  if (!authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'AUTH_REQUIRED' });
  }

  const token = authHeader.slice(7);
  
  try {
    const auth = getFirebaseAuth();
    if (!auth) {
      return res.status(503).json({ error: 'AUTH_SERVICE_UNAVAILABLE' });
    }

    const decoded = await auth.verifyIdToken(token);
    req.firebaseUid = decoded.uid;
    
    // Load user from database. Phase B/C convergence enabler: an app user may
    // have a Firebase identity but no Postgres `users` row yet (they never hit
    // the legacy-shop buyer sync), so v1 endpoints must provision the row the
    // same way legacy-shop's resolveShopBuyer does — otherwise every /api/v1/*
    // call returns 401 USER_NOT_FOUND for that seller.
    const prisma = getPrisma();
    let user = await prisma.user.findUnique({
      where: { firebaseUid: decoded.uid },
      select: {
        id: true,
        firebaseUid: true,
        email: true,
        role: true,
        accountStatus: true,
      },
    });

    if (!user) {
      const rec = await getFirebaseAuth().getUser(decoded.uid);
      user = await prisma.user.create({
        data: {
          firebaseUid: decoded.uid,
          email: rec.email || null,
          phone: rec.phoneNumber || null,
          displayName: rec.displayName || null,
          accountStatus: 'active',
          phoneVerified: Boolean(rec.phoneNumber),
        },
        select: {
          id: true,
          firebaseUid: true,
          email: true,
          role: true,
          accountStatus: true,
        },
      });
    }

    if (user.accountStatus === 'deleted') {
      return res.status(403).json({ error: 'ACCOUNT_DELETED' });
    }

    if (user.accountStatus === 'suspended') {
      return res.status(403).json({ error: 'ACCOUNT_SUSPENDED' });
    }

    req.user = user;
    recordUserActivity(user.id);
    next();
  } catch (error) {
    if (error.code === 'auth/id-token-expired') {
      return res.status(401).json({ error: 'TOKEN_EXPIRED' });
    }
    if (error.code === 'auth/id-token-revoked') {
      return res.status(401).json({ error: 'TOKEN_REVOKED' });
    }
    return res.status(401).json({ error: 'INVALID_TOKEN' });
  }
}

// Optional authentication - attaches user if token present, continues if not
async function optionalAuth(req, res, next) {
  const authHeader = req.headers.authorization || '';
  
  if (!authHeader.startsWith('Bearer ')) {
    req.user = null;
    return next();
  }

  const token = authHeader.slice(7);
  
  try {
    const auth = getFirebaseAuth();
    if (!auth) {
      req.user = null;
      return next();
    }

    const decoded = await auth.verifyIdToken(token);
    req.firebaseUid = decoded.uid;
    
    const prisma = getPrisma();
    const user = await prisma.user.findUnique({
      where: { firebaseUid: decoded.uid },
      select: {
        id: true,
        firebaseUid: true,
        email: true,
        role: true,
        accountStatus: true,
      },
    });

    req.user = user;
    if (user) recordUserActivity(user.id);
    next();
  } catch (error) {
    req.user = null;
    next();
  }
}

// Require specific role
function requireRole(...roles) {
  return (req, res, next) => {
    if (!req.user) {
      return res.status(401).json({ error: 'AUTH_REQUIRED' });
    }

    if (!roles.includes(req.user.role)) {
      return res.status(403).json({ error: 'FORBIDDEN' });
    }

    next();
  };
}

// Require account to be active
function requireActive(req, res, next) {
  if (!req.user) {
    return res.status(401).json({ error: 'AUTH_REQUIRED' });
  }

  if (req.user.accountStatus !== 'active') {
    return res.status(403).json({ error: 'ACCOUNT_NOT_ACTIVE' });
  }

  next();
}

// Verify admin secret or Firebase admin role.
// Secret comparison is timing-safe and fails closed when ADMIN_SECRET is missing.
function validAdminSecret(candidate) {
  const expected = config.security.adminSecret;
  if (!candidate || !expected) return false;
  const a = Buffer.from(String(candidate));
  const b = Buffer.from(String(expected));
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

async function verifyAdmin(req, res, next) {
  const secret = req.headers['x-admin-secret'];

  if (validAdminSecret(secret)) {
    req.isAdmin = true;
    return next();
  }

  if (!req.user) {
    return res.status(401).json({ error: 'AUTH_REQUIRED' });
  }

  if (!['admin', 'super_admin'].includes(req.user.role)) {
    return res.status(403).json({ error: 'ADMIN_REQUIRED' });
  }

  req.isAdmin = true;
  next();
}

// The single admin gate: x-admin-secret only. No Firebase path — the panel
// and all admin tooling authenticate with the shared secret, so there is
// exactly one login method on backend and UI alike.
function authenticateAdmin(req, res, next) {
  const secret = req.headers['x-admin-secret'];

  if (secret && secret === config.security.adminSecret) {
    req.isAdmin = true;
    return next();
  }

  return res.status(401).json({ error: 'AUTH_REQUIRED' });
}

// Active-account gate that also passes secret-authenticated admin calls,
// which carry no req.user because no Firebase token was presented.
function requireActiveAdmin(req, res, next) {
  if (!req.user) {
    if (req.isAdmin) return next();
    return res.status(401).json({ error: 'AUTH_REQUIRED' });
  }

  if (req.user.accountStatus !== 'active') {
    return res.status(403).json({ error: 'ACCOUNT_NOT_ACTIVE' });
  }

  next();
}

module.exports = {
  authenticate,
  optionalAuth,
  requireRole,
  requireActive,
  verifyAdmin,
  authenticateAdmin,
  requireActiveAdmin,
};
