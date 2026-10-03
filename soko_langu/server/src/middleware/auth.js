const { getFirebaseAuth } = require('../config/firebase');
const { getStore } = require('../config/database');
const { recordUserActivity } = require('../services/activity');
const crypto = require('crypto');
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
    // Session age for requireFreshSession (logout-all enforcement). Survives
    // silent refresh: Firebase keeps the session's original auth_time.
    req.authTime = decoded.auth_time || 0;

    // Load user from database. Phase B/C convergence enabler: an app user may
    // have a Firebase identity but no Postgres `users` row yet (they never hit
    // the legacy-shop buyer sync), so v1 endpoints must provision the row the
    // same way legacy-shop's resolveShopBuyer does — otherwise every /api/v1/*
    // call returns 401 USER_NOT_FOUND for that seller.
    const store = getStore();
    let user = await store.user.findUnique({
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
      user = await store.user.create({
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
    
    const store = getStore();
    const user = await store.user.findUnique({
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

// Require account to be active AND the session to be fresh (not revoked by
// logout-all, password-reset recovery, or admin suspension). This is the
// choke point: ~55 authenticated-action routes mount it, so revocation bites
// everywhere it matters with one check. Secret-authenticated admin calls
// never reach here (they use requireActiveAdmin), and read-only routes that
// mount bare `authenticate` keep the 1h ID-token bound without an extra read.
async function requireActive(req, res, next) {
  if (!req.user) {
    return apiError(res, 401, 'AUTH_REQUIRED');
  }

  if (req.user.accountStatus !== 'active') {
    return apiError(res, 403, 'ACCOUNT_NOT_ACTIVE');
  }

  try {
    const { isSessionRevoked } = require('../services/session-revocation');
    if (await isSessionRevoked(req.firebaseUid, req.authTime)) {
      return apiError(res, 401, 'SESSION_REVOKED');
    }
  } catch (e) {
    // Same fail-open rationale as requireFreshSession: the token verified,
    // so a revocation-store blip must not lock users out of money routes.
    console.error('[AUTH] revocation check failed:', e.message);
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
//
// checkRevoked is intentionally NOT enabled on verifyIdToken anywhere in this
// file: every OTP sign-in (phone + email) uses signInWithCustomToken
// (auth_repository.dart), and Firebase only supports revocation checks for
// native identity-provider sign-ins — the check throws for custom-token
// sessions, so enabling it would 401 every OTP user on the first request.
// Session death on suspension is instead enforced by the accountStatus/
// isSuspended gates on money-touching routes.
function authenticateAdmin(req, res, next) {
  const secret = req.headers['x-admin-secret'];
  const expected = config.security.adminSecret;

  // timingSafeEqual throws on length mismatch, so the length gate is the
  // constant-time side channel here; both branches cost ~the same.
  if (
    secret &&
    expected &&
    typeof secret === 'string' &&
    secret.length === expected.length &&
    crypto.timingSafeEqual(Buffer.from(secret), Buffer.from(expected))
  ) {
    req.isAdmin = true;
    return next();
  }

  return apiError(res, 401, 'AUTH_REQUIRED');
}

// Rejects tokens minted before the user's sessionRevokedAt stamp (logout-all,
// password-reset recovery, admin suspension). Mount AFTER authenticate on
// routes where a stolen session must die immediately (money, admin,
// auth-sensitive) — NOT globally, so one extra Firestore read is only paid
// where revocation latency matters; everywhere else the 1h ID-token expiry
// plus the suspended/deleted gates above already bound the window.
async function requireFreshSession(req, res, next) {
  if (!req.firebaseUid) {
    return apiError(res, 401, 'AUTH_REQUIRED');
  }
  try {
    const { isSessionRevoked } = require('../services/session-revocation');
    if (await isSessionRevoked(req.firebaseUid, req.authTime)) {
      return apiError(res, 401, 'SESSION_REVOKED');
    }
  } catch (e) {
    // A revocation-store outage must not lock every user out: the token
    // itself already verified, so fail open here and log loudly. (Deliberate
    // asymmetry with throttles: availability of money routes during a
    // Firestore blip outweighs instant revocation, and the stamp is still
    // enforced on the next healthy request.)
    console.error('[AUTH] revocation check failed:', e.message);
  }
  next();
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
  requireFreshSession,
  verifyAdmin,
  authenticateAdmin,
  requireActiveAdmin,
};
