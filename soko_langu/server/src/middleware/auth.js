const { getFirebaseAuth } = require('../config/firebase');
const { getStore } = require('../config/database');
const { recordUserActivity } = require('../services/activity');
const crypto = require('crypto');
const config = require('../config');
const { jsonError } = require('../utils/http');
const accountStore = require('../services/account-store');

// Middleware errors keep `error` as the machine code (client parses it today)
// while `jsonError` adds the §25 envelope fields.
function apiError(res, status, code) {
  return jsonError(res, { status, code });
}

function isBootstrapSuperAdminEmail(email) {
  if (!email) return false;
  const list = config.security && config.security.superAdminEmails;
  return Array.isArray(list) && list.includes(String(email).trim().toLowerCase());
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
      const email = rec.email || null;
      const superAdmin = isBootstrapSuperAdminEmail(email);
      user = await store.user.create({
        data: {
          firebaseUid: decoded.uid,
          email,
          phone: rec.phoneNumber || null,
          displayName: rec.displayName || null,
          accountStatus: 'active',
          phoneVerified: Boolean(rec.phoneNumber),
          ...(superAdmin ? { role: 'super_admin', isAdmin: true } : {}),
        },
        select: {
          id: true,
          firebaseUid: true,
          email: true,
          role: true,
          accountStatus: true,
        },
      });
      if (superAdmin) {
        await getStore().user.update({ where: { id: user.id }, data: { role: 'super_admin', isAdmin: true } }).catch(() => {});
        try {
          const fs = require('../config/firebase').getFirebaseFirestore();
          if (fs) await fs.collection('users').doc(decoded.uid).set({ role: 'super_admin', isAdmin: true, email, updatedAt: new Date().toISOString() }, { merge: true });
        } catch (_) {}
        await accountStore.writeProfile(decoded.uid, {
          col: { email, displayName: rec.displayName || null, accountStatus: 'active' },
          meta: { profile: {} },
        }).catch(() => {});
      }
    } else if (isBootstrapSuperAdminEmail(user.email || decoded.email) && user.role !== 'super_admin') {
      try {
        const store = getStore();
        await store.user.update({ where: { id: user.id }, data: { role: 'super_admin', isAdmin: true } });
        user.role = 'super_admin';
        try {
          const fs = require('../config/firebase').getFirebaseFirestore();
          if (fs) await fs.collection('users').doc(decoded.uid).set({ role: 'super_admin', isAdmin: true, email: user.email || decoded.email || null, updatedAt: new Date().toISOString() }, { merge: true });
        } catch (_) {}
      } catch (_) {}
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

// Legacy alias for the single admin gate. A second, weaker implementation let
// routes outside /admin (disputes, products, refunds, moderation, referrals)
// accept the shared secret without the TOTP step-up enforced by
// authenticateAdmin. Delegating keeps one rule everywhere.
async function verifyAdmin(req, res, next) {
  return authenticateAdmin(req, res, next);
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
function decryptAdminSecret(blob) {
  const crypto = require('crypto');
  const raw = Buffer.from(String(blob), 'base64');
  const iv = raw.slice(0, 12);
  const tag = raw.slice(12, 28);
  const enc = raw.slice(28);
  const key = crypto.createHash('sha256').update(String(process.env.ENCRYPTION_KEY || process.env.ADMIN_SECRET || 'soko-vibe')).digest();
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(enc), decipher.final()]).toString('utf8');
}

async function authenticateAdmin(req, res, next) {
  const secret = req.headers['x-admin-secret'];
  const expected = config.security.adminSecret;

  // Staff session token (admin_staff + staff_sessions). Checked before the
  // shared secret so a staff member never needs the owner's break-glass key.
  // Previously the login endpoint issued these tokens but no middleware ever
  // validated them, and the issued expiry used serverTimestamp() (i.e. "now"),
  // so staff accounts were effectively unusable and permissions unenforced.
  const staffToken = req.headers['x-staff-token'];
  if (staffToken && typeof staffToken === 'string' && /^[a-f0-9]{32,128}$/i.test(staffToken)) {
    try {
      const commerceStore = require('../services/commerce-store');
      const session = await commerceStore.getDocument('staff_sessions', staffToken);
      if (session) {
        const expiresMs = session.expiresAtMs
          ? Number(session.expiresAtMs)
          : session.expiresAt && typeof session.expiresAt.toMillis === 'function'
            ? session.expiresAt.toMillis()
            : new Date(session.expiresAt || 0).getTime();
        if (!Number.isFinite(expiresMs) || expiresMs < Date.now()) {
          return apiError(res, 401, 'STAFF_SESSION_EXPIRED');
        }
        const staff = await commerceStore.getDocument('admin_staff', session.staffId);
        if (!staff || staff.active === false) {
          return apiError(res, 403, 'STAFF_INACTIVE');
        }
        req.isAdmin = true;
        req.adminStaff = {
          id: session.staffId,
          email: staff.email || session.email || null,
          name: staff.name || session.name || '',
          role: staff.role || session.role || 'support',
          permissions: Array.isArray(staff.permissions) ? staff.permissions : null,
        };
        return next();
      }
    } catch (e) {
      console.error('[AUTH] staff session lookup failed:', e && e.message);
      return apiError(res, 503, 'STAFF_AUTH_UNAVAILABLE');
    }
  }

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
    // MFA (TOTP) enforcement for secret-based admin.
    try {
      const commerceStore = require('../services/commerce-store');
      const totp = require('../services/totp');
      commerceStore.getDocument('users', 'admin-secret').then((doc) => {
        const mfa = doc && doc.mfa;
        if (mfa && mfa.enabled && mfa.secret) {
          let sec = null;
          try { sec = decryptAdminSecret(mfa.secret); } catch (_) { sec = null; }
          const code = req.headers['x-admin-totp'];
          if (!sec || !totp.verify(sec, code)) {
            return apiError(res, 401, 'MFA_REQUIRED');
          }
        }
        next();
      }).catch((err) => {
        // Cannot know whether MFA is enrolled, so production fails closed.
        // Development stays usable without a Firestore emulator; set
        // ADMIN_MFA_STRICT=false only to accept that risk deliberately.
        console.error('[AUTH] admin MFA lookup failed:', err && err.message);
        if (config.nodeEnv === 'production' && process.env.ADMIN_MFA_STRICT !== 'false') {
          return apiError(res, 503, 'MFA_UNAVAILABLE');
        }
        next();
      });
      return; // async path
    } catch (_) {
      req.isAdmin = true;
      return next();
    }
  }

  const authHeader = req.headers.authorization || '';
  if (authHeader.startsWith('Bearer ')) {
    try {
      const auth = getFirebaseAuth();
      if (auth) {
        const decoded = await auth.verifyIdToken(authHeader.slice(7));
        const store = getStore();
        let user = await store.user.findUnique({
          where: { firebaseUid: decoded.uid },
          select: { id: true, firebaseUid: true, email: true, role: true, accountStatus: true },
        });
        const email = (user && user.email) || decoded.email || null;
        const allowed = isBootstrapSuperAdminEmail(email) || (user && ['admin', 'super_admin'].includes(user.role));
        if (!allowed) return apiError(res, 403, 'ADMIN_REQUIRED');
        if (isBootstrapSuperAdminEmail(email) && user && user.role !== 'super_admin') {
          await store.user.update({ where: { id: user.id }, data: { role: 'super_admin', isAdmin: true } }).catch(() => {});
          user.role = 'super_admin';
          try {
            const fs = require('../config/firebase').getFirebaseFirestore();
            if (fs) await fs.collection('users').doc(decoded.uid).set({ role: 'super_admin', isAdmin: true, email, updatedAt: new Date().toISOString() }, { merge: true });
          } catch (_) {}
        }
        req.isAdmin = true;
        req.firebaseUid = decoded.uid;
        req.user = user ? { ...user, role: user.role || (isBootstrapSuperAdminEmail(email) ? 'super_admin' : user.role) } : { firebaseUid: decoded.uid, email, role: 'super_admin', accountStatus: 'active' };
        return next();
      }
    } catch (_) {
      return apiError(res, 401, 'INVALID_TOKEN');
    }
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
