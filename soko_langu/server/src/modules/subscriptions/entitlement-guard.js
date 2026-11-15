// Entitlement guard middleware. Use: router.get('/x', requireEntitlement('advanced_analytics'), handler)
const service = require('./subscription-service');
const { jsonError } = require('../../utils/http');

function requireEntitlement(feature) {
  return async (req, res, next) => {
    const authHeader = req.headers.authorization || '';
    if (!authHeader.startsWith('Bearer ')) {
      jsonError(res, { status: 401, code: 'UNAUTHENTICATED' }); return;
    }
    try {
      const { getFirebaseAuth } = require('../../config/firebase');
      const decoded = await getFirebaseAuth().verifyIdToken(authHeader.slice(7));
      const ent = await service.resolveEntitlements(decoded.uid);
      const features = Array.isArray(ent.features) ? ent.features : [];
      if (!features.includes(feature) && !features.includes('*')) {
        jsonError(res, { status: 403, code: 'ENTITLEMENT_REQUIRED', message: `Feature ${feature} requires a higher plan` });
        return;
      }
      req.user = { id: decoded.uid, entitlements: ent };
      next();
    } catch (e) {
      jsonError(res, { status: 401, code: 'INVALID_TOKEN', message: e.message });
    }
  };
}

module.exports = { requireEntitlement };