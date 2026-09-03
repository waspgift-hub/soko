const { getFirebaseAuth } = require('../config/firebase');
const { getPrisma } = require('../config/database');
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
    
    // Load user from database
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

    if (!user) {
      return res.status(401).json({ error: 'USER_NOT_FOUND' });
    }

    if (user.accountStatus === 'deleted') {
      return res.status(403).json({ error: 'ACCOUNT_DELETED' });
    }

    if (user.accountStatus === 'suspended') {
      return res.status(403).json({ error: 'ACCOUNT_SUSPENDED' });
    }

    req.user = user;
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

// Verify admin secret or admin role
async function verifyAdmin(req, res, next) {
  const secret = req.headers['x-admin-secret'];
  
  if (secret && secret === config.security.adminSecret) {
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

module.exports = {
  authenticate,
  optionalAuth,
  requireRole,
  requireActive,
  verifyAdmin,
};
