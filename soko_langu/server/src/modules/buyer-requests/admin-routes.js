const express = require('express');
const router = express.Router();
const { authenticateAdmin, requireActiveAdmin } = require('../../middleware/auth');
const { requireAdminPermission } = require('../../middleware/admin-rbac');
const { jsonError } = require('../../utils/http');
const { writeAudit, auditFromReq } = require('../../services/audit');
const service = require('./request-service');

router.use(authenticateAdmin);
router.use(requireActiveAdmin);

function wrap(handler) {
  return async (req, res) => {
    try {
      const data = await handler(req, res);
      if (res.headersSent) return;
      res.json({ success: true, data });
    } catch (e) {
      const status = Number(e && e.status) || 500;
      const code = (e && e.code) || 'BUYER_REQUEST_ADMIN_ERROR';
      jsonError(res, { status, code, message: e && e.message ? e.message : code });
    }
  };
}

router.get('/dashboard', requireAdminPermission('users:read'), wrap(async () => {
  return service.adminDashboard();
}));

router.get('/config', requireAdminPermission('settings:write'), wrap(async () => {
  return service.adminConfig();
}));

router.put('/config', requireAdminPermission('settings:write'), wrap(async (req) => {
  const before = await service.adminConfig();
  const after = await service.adminUpdateConfig(req.body || {});
  await writeAudit({
    ...auditFromReq(req),
    action: 'BUYER_REQUEST_CONFIG_UPDATE',
    entityType: 'buyer_request_policy',
    entityId: 'buyerRequests',
    oldState: before.policy,
    newState: after.policy,
  });
  return after;
}));

router.get('/requests', requireAdminPermission('users:read'), wrap(async (req) => {
  return service.adminListRequests({
    status: req.query && req.query.status,
    buyerUid: req.query && req.query.buyerUid,
    page: req.query && req.query.page,
    limit: req.query && req.query.limit,
  });
}));

router.get('/requests/:id', requireAdminPermission('users:read'), wrap(async (req) => {
  return service.adminDetail({ requestId: req.params.id });
}));

router.get('/requests/:id/activity', requireAdminPermission('users:read'), wrap(async (req) => {
  return service.getHistory({
    requestId: req.params.id,
    buyerUid: req.query && req.query.buyerUid,
    viewerRole: 'admin',
  });
}));

router.post('/requests/:id/moderate', requireAdminPermission('users:write'), wrap(async (req) => {
  const before = await service.getDetail({ requestId: req.params.id, viewerUid: null, nowMs: Date.now() });
  const result = await service.adminModerate({
    requestId: req.params.id,
    action: String(req.body && req.body.action || ''),
    reason: String(req.body && req.body.reason || ''),
    hourList: req.body && req.body.hours,
    adminId: (req.adminStaff && req.adminStaff.id) || (req.user && req.user.id) || null,
    nowMs: Date.now(),
  });
  await writeAudit({
    ...auditFromReq(req),
    action: `BUYER_REQUEST_${String(req.body && req.body.action || '').toUpperCase()}`,
    entityType: 'buyer_request',
    entityId: req.params.id,
    oldState: before && before.status,
    newState: result && result.status,
  });
  return result;
}));

router.post('/requests/:id/offers/:offerId/moderate', requireAdminPermission('users:write'), wrap(async (req) => {
  const result = await service.adminModerateOffer({
    requestId: req.params.id,
    offerId: req.params.offerId,
    action: String(req.body && req.body.action || 'review'),
    reason: String(req.body && req.body.reason || ''),
    adminId: (req.adminStaff && req.adminStaff.id) || (req.user && req.user.id) || null,
    nowMs: Date.now(),
  });
  await writeAudit({
    ...auditFromReq(req),
    action: 'BUYER_REQUEST_OFFER_MODERATED',
    entityType: 'buyer_request_offer',
    entityId: req.params.offerId,
    newState: result.offer && result.offer.status,
  });
  return result;
}));

module.exports = router;
