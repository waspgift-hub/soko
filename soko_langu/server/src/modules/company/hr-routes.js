'use strict';
const { Router } = require('express');
const { authenticate } = require('../../middleware/auth');
const { loadCompanyMembership } = require('./membership');
const rbac = require('./rbac');
const hr = require('./hr');

const router = Router();
router.use(authenticate);
router.use(loadCompanyMembership);

router.get('/employees', rbac.requireCompanyMember, rbac.requirePermission('employees', 'read'), async (req, res, next) => {
  try { res.json({ success: true, data: await hr.listEmployees({ legalEntityId: req.query.legalEntityId, department: req.query.department, status: req.query.status }) }); }
  catch (e) { next(e); }
});
router.post('/employees', rbac.requireCompanyMember, rbac.requirePermission('employees', 'create'), async (req, res, next) => {
  try { const d = await hr.createEmployee(req.body || {}, req.firebaseUid); res.status(201).json({ success: true, data: d }); }
  catch (e) { next(e); }
});
router.get('/employees/:id', rbac.requireCompanyMember, rbac.requirePermission('employees', 'read'), async (req, res, next) => {
  try { const d = await hr.getEmployee(req.params.id); if (!d) return res.status(404).json({ success: false, code: 'NOT_FOUND' }); res.json({ success: true, data: d }); }
  catch (e) { next(e); }
});
router.put('/employees/:id', rbac.requireCompanyMember, rbac.requirePermission('employees', 'edit'), async (req, res, next) => {
  try { res.json({ success: true, data: await hr.updateEmployee(req.params.id, req.body || {}, req.firebaseUid) }); }
  catch (e) { next(e); }
});
router.get('/departments', rbac.requireCompanyMember, rbac.requirePermission('employees', 'read'), async (req, res, next) => {
  try { res.json({ success: true, data: await hr.listDepartments(req.query.legalEntityId) }); }
  catch (e) { next(e); }
});
router.post('/departments', rbac.requireCompanyMember, rbac.requirePermission('employees', 'create'), async (req, res, next) => {
  try { const d = await hr.createDepartment(req.body || {}, req.firebaseUid); res.status(201).json({ success: true, data: d }); }
  catch (e) { next(e); }
});
router.get('/leave', rbac.requireCompanyMember, rbac.requirePermission('employees', 'read'), async (req, res, next) => {
  try { res.json({ success: true, data: await hr.listLeave({ employeeUid: req.query.employeeUid, status: req.query.status }) }); }
  catch (e) { next(e); }
});
router.post('/leave', rbac.requireCompanyMember, rbac.requirePermission('employees', 'create'), async (req, res, next) => {
  try { const d = await hr.createLeave(req.body || {}, req.firebaseUid); res.status(201).json({ success: true, data: d }); }
  catch (e) { next(e); }
});
router.post('/leave/:id/decision', rbac.requireCompanyMember, rbac.requirePermission('employees', 'approve'), async (req, res, next) => {
  try {
    const decision = req.body?.decision === 'approve' ? 'approve' : 'reject';
    const d = await hr.decideLeave(req.params.id, decision, req.firebaseUid, req.body?.reason || '');
    res.json({ success: true, data: d });
  } catch (e) { next(e); }
});

module.exports = router;
PY