'use strict';
const { Router } = require('express');
const { authenticate } = require('../../middleware/auth');
const { loadCompanyMembership } = require('./membership');
const rbac = require('./rbac');
const calendar = require('./calendar');

const router = Router();
router.use(authenticate);
router.use(loadCompanyMembership);

router.get('/events', rbac.requireCompanyMember, rbac.requirePermission('calendar', 'read'), async (req, res, next) => {
  try { res.json({ success: true, data: await calendar.listEvents({ legalEntityId: req.query.legalEntityId, from: req.query.from, to: req.query.to }) }); }
  catch (e) { next(e); }
});
router.post('/events', rbac.requireCompanyMember, rbac.requirePermission('calendar', 'create'), async (req, res, next) => {
  try { const d = await calendar.createEvent(req.body || {}, req.firebaseUid); res.status(201).json({ success: true, data: d }); }
  catch (e) { next(e); }
});
router.put('/events/:id', rbac.requireCompanyMember, rbac.requirePermission('calendar', 'edit'), async (req, res, next) => {
  try { res.json({ success: true, data: await calendar.updateEvent(req.params.id, req.body || {}, req.firebaseUid) }); }
  catch (e) { next(e); }
});
router.delete('/events/:id', rbac.requireCompanyMember, rbac.requirePermission('calendar', 'delete'), async (req, res, next) => {
  try { res.json({ success: true, data: await calendar.deleteEvent(req.params.id, req.firebaseUid) }); }
  catch (e) { next(e); }
});

module.exports = router;
PY