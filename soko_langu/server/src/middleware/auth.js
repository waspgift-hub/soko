const { getFirebaseAuth } = require('../config/firebase');
const { getPrisma } = require('../config/database');
const { recordUserActivity } = require('../services/activity');
const config = require('../config');
const { jsonError } = require('../utils/http');

// Middleware errors keep `error` as the machine code (client parses it today)
// while `jsonError` adds the §25 envelope fields.
function apiError(res, status, code) {
  return jsonError(res, { status, code });
}

// Verify Firebase ID token and attach user to request
async function authenticate(req, res, next) {
  const authHeader = req.headers.authorization || '';
  
  if (!authHeader.startsWith('Bearer ')) {
    return apiError(res, 401, 'AUTH_REQUIRED');
  }

  const token = authHeader.slice(7);
  
  try {
    const auth = getFirebaseAuth();
    if (!auth) {
      return apiError(res, 503, 'AUTH_SERVICE_UNAVAILABLE');
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
      return apiError(res, 403, 'ACCOUNT_DELETED');
    }

    if (user.accountStatus === 'suspended') {
      return apiError(res, 403, 'ACCOUNT_SUSPENDED');
    }

    req.user = user;
    recordUserActivity(user.id);
    next();
  } catch (error) {
    if (error.code === 'auth/id-token-expired') {
      return apiError(res, 401, 'TOKEN_EXPIRED');
    }
    if (error.code === 'auth/id-token-revoked') {
      return apiError(res, 401, 'TOKEN_REVOKED');
    }
    return apiError(res, 401, 'INVALID_TOKEN');
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
      return apiError(res, 401, 'AUTH_REQUIRED');
    }

    if (!roles.includes(req.user.role)) {
      return apiError(res, 403, 'FORBIDDEN');
    }

    next();
  };
}

// Require account to be active
function requireActive(req, res, next) {
  if (!req.user) {
    return apiError(res, 401, 'AUTH_REQUIRED');
  }

  if (req.user.accountStatus !== 'active') {
    return apiError(res, 403, 'ACCOUNT_NOT_ACTIVE');
  }

  next();
}

// Verify admin secret or admin role
async function verifyAdmin(req, res, next) {
  const secret = req.headers['x-admin-secret'];
  
  if (secret && secret === config.security.adminSecret) {
    req.isAdmin = true;
    return next();
  }

  if (!req.user) {
    return apiError(res, 401, 'AUTH_REQUIRED');
  }

  if (!['admin', 'super_admin'].includes(req.user.role)) {
    return apiError(res, 403, 'ADMIN_REQUIRED');
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

  return apiError(res, 401, 'AUTH_REQUIRED');
}

// Active-account gate that also passes secret-authenticated admin calls,
// which carry no req.user because no Firebase token was presented.
function requireActiveAdmin(req, res, next) {
  if (!req.user) {
    if (req.isAdmin) return next();
    return apiError(res, 401, 'AUTH_REQUIRED');
  }

  if (req.user.accountStatus !== 'active') {
    return apiError(res, 403, 'ACCOUNT_NOT_ACTIVE');
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
