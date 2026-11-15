const { Router } = require('express');
const { getFirebaseAuth } = require('../../../config/firebase');
const creditService = require('./credit-service');
const { jsonError } = require('../../../utils/http');

const router = Router();

async function requireUser(req, res) {
  const authHeader = req.headers.authorization || '';
  if (!authHeader.startsWith('Bearer ')) { jsonError(res, { status: 401, code: 'UNAUTHENTICATED' }); return null; }
  try {
    const auth = getFirebaseAuth();
    const decoded = await auth.verifyIdToken(authHeader.slice(7));
    return { id: decoded.uid };
  } catch { jsonError(res, { status: 401, code: 'INVALID_TOKEN' }); return null; }
}

function guard(handler) {
  return async (req, res) => {
    const user = await requireUser(req, res);
    if (!user) return;
    try { await handler(req, res, user.id); }
    catch (err) { jsonError(res, { status: err.status || 500, code: err.code || 'CREDIT_ERROR', message: err.message }); }
  };
}

router.get('/balance', guard(async (req, res, userId) => {
  res.json({ success: true, data: await creditService.getBalance(userId) });
}));

router.post('/topup', guard(async (req, res, userId) => {
  const { packageId, phone } = req.body || {};
  const result = await creditService.topUp({ userId, packageId, phone });
  res.status(201).json({ success: true, data: result });
}));

router.get('/ledger', guard(async (req, res, userId) => {
  res.json({ success: true, data: await creditService.getLedger(userId) });
}));

router.post('/webhook/azampay', async (req, res) => {
  try {
    const sig = req.headers['x-azampay-signature'] || req.headers['x-signature'] || '';
    const result = await creditService.handleTopUpWebhook(req.body, sig);
    res.json({ success: true, data: result });
  } catch (err) {
    jsonError(res, { status: err.status || 400, code: err.code || 'WEBHOOK_ERROR', message: err.message });
  }
});

module.exports = router;