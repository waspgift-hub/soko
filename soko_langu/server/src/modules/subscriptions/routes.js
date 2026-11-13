const { Router } = require('express');
const { getFirebaseAuth } = require('../../config/firebase');
const store = require('./subscription-store');
const service = require('./subscription-service');
const { PLANS, SUBSCRIPTION_STATUS } = require('./plans');
const { jsonError } = require('../../utils/http');

const router = Router();

async function requireUser(req, res) {
  const authHeader = req.headers.authorization || '';
  if (!authHeader.startsWith('Bearer ')) {
    jsonError(res, { status: 401, code: 'UNAUTHENTICATED', message: 'Missing or invalid token' });
    return null;
  }
  try {
    const auth = getFirebaseAuth();
    if (!auth) {
      jsonError(res, { status: 503, code: 'AUTH_NOT_CONFIGURED', message: 'Auth not configured' });
      return null;
    }
    const decoded = await auth.verifyIdToken(authHeader.slice(7));
    return { id: decoded.uid };
  } catch {
    jsonError(res, { status: 401, code: 'INVALID_TOKEN', message: 'Invalid token' });
    return null;
  }
}

function guard(handler) {
  return async (req, res) => {
    const user = await requireUser(req, res);
    if (!user) return;
    try {
      await handler(req, res, user.id);
    } catch (err) {
      jsonError(res, { status: err.status || 500, code: err.code || 'SUBSCRIPTION_ERROR', message: err.message });
    }
  };
}

router.get('/plans', (_req, res) => {
  res.json({ success: true, data: Object.values(PLANS) });
});

router.get('/entitlements', guard(async (req, res, userId) => {
  res.json({ success: true, data: await service.resolveEntitlements(userId) });
}));

router.get('/subscription', guard(async (req, res, userId) => {
  const sub = await store.getSubscription({ userId });
  res.json({ success: true, data: sub });
}));

router.post('/trial', guard(async (req, res, userId) => {
  const planId = String(req.body?.planId || '');
  const sub = await service.startTrial({ userId, planId });
  res.status(201).json({ success: true, data: sub });
}));

router.get('/ai-quota', guard(async (req, res, userId) => {
  const ent = await service.resolveEntitlements(userId);
  const dateKey = store.todayKey();
  const used = await store.getAiUsage({ userId, dateKey });
  res.json({ success: true, data: { used, limit: ent.aiActionsPerDay, planId: ent.planId, dateKey } });
}));

module.exports = router;