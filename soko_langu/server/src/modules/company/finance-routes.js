'use strict';
const { Router } = require('express');
const { authenticate } = require('../../middleware/auth');
const { loadCompanyMembership } = require('./membership');
const rbac = require('./rbac');
const finance = require('./finance');

const router = Router();
router.use(authenticate);
router.use(loadCompanyMembership);

router.get('/accounts', rbac.requireCompanyMember, rbac.requirePermission('finance', 'read'), async (req, res, next) => {
  try { res.json({ success: true, data: await finance.listAccounts(req.query.legalEntityId) }); }
  catch (e) { next(e); }
});
router.post('/accounts', rbac.requireCompanyMember, rbac.requirePermission('finance', 'configure'), async (req, res, next) => {
  try { const d = await finance.createAccount(req.body || {}, req.firebaseUid); res.status(201).json({ success: true, data: d }); }
  catch (e) { next(e); }
});
router.get('/budgets', rbac.requireCompanyMember, rbac.requirePermission('finance', 'read'), async (req, res, next) => {
  try { res.json({ success: true, data: await finance.listBudgets({ legalEntityId: req.query.legalEntityId, department: req.query.department, projectId: req.query.projectId }) }); }
  catch (e) { next(e); }
});
router.post('/budgets', rbac.requireCompanyMember, rbac.requirePermission('finance', 'create'), async (req, res, next) => {
  try { const d = await finance.createBudget(req.body || {}, req.firebaseUid); res.status(201).json({ success: true, data: d }); }
  catch (e) { next(e); }
});
router.get('/invoices', rbac.requireCompanyMember, rbac.requirePermission('finance', 'read'), async (req, res, next) => {
  try { res.json({ success: true, data: await finance.listInvoices({ legalEntityId: req.query.legalEntityId, type: req.query.type, status: req.query.status }) }); }
  catch (e) { next(e); }
});
router.post('/invoices', rbac.requireCompanyMember, rbac.requirePermission('finance', 'create'), async (req, res, next) => {
  try { const d = await finance.createInvoice(req.body || {}, req.firebaseUid); res.status(201).json({ success: true, data: d }); }
  catch (e) { next(e); }
});
router.post('/invoices/:id/status', rbac.requireCompanyMember, rbac.requirePermission('finance', 'approve'), async (req, res, next) => {
  try { res.json({ success: true, data: await finance.updateInvoiceStatus(req.params.id, req.body?.status, req.firebaseUid, req.body?.reason || '') }); }
  catch (e) { next(e); }
});
router.get('/expenses', rbac.requireCompanyMember, rbac.requirePermission('finance', 'read'), async (req, res, next) => {
  try { res.json({ success: true, data: await finance.listExpenses({ legalEntityId: req.query.legalEntityId, department: req.query.department, status: req.query.status }) }); }
  catch (e) { next(e); }
});
router.post('/expenses', rbac.requireCompanyMember, rbac.requirePermission('finance', 'create'), async (req, res, next) => {
  try { const d = await finance.createExpense(req.body || {}, req.firebaseUid); res.status(201).json({ success: true, data: d }); }
  catch (e) { next(e); }
});
router.post('/expenses/:id/decision', rbac.requireCompanyMember, rbac.requirePermission('finance', 'approve'), async (req, res, next) => {
  try {
    const decision = req.body?.decision === 'approve' ? 'approve' : 'reject';
    res.json({ success: true, data: await finance.decideExpense(req.params.id, decision, req.firebaseUid, req.body?.reason || '') });
  } catch (e) { next(e); }
});
router.get('/journals', rbac.requireCompanyMember, rbac.requirePermission('finance', 'read'), async (req, res, next) => {
  try { res.json({ success: true, data: await finance.listJournals({ legalEntityId: req.query.legalEntityId, status: req.query.status }) }); }
  catch (e) { next(e); }
});
router.post('/journals', rbac.requireCompanyMember, rbac.requirePermission('finance', 'create'), async (req, res, next) => {
  try { const d = await finance.createJournal(req.body || {}, req.firebaseUid); res.status(201).json({ success: true, data: d }); }
  catch (e) { next(e); }
});
router.post('/journals/:id/post', rbac.requireCompanyMember, rbac.requirePermission('finance', 'approve'), async (req, res, next) => {
  try { res.json({ success: true, data: await finance.postJournal(req.params.id, req.firebaseUid) }); }
  catch (e) { next(e); }
});
router.post('/journals/:id/reverse', rbac.requireCompanyMember, rbac.requirePermission('finance', 'administer'), async (req, res, next) => {
  try { res.json({ success: true, data: await finance.reverseJournal(req.params.id, req.firebaseUid, req.body?.reason || '') }); }
  catch (e) { next(e); }
});
router.get('/payments', rbac.requireCompanyMember, rbac.requirePermission('finance', 'read'), async (req, res, next) => {
  try { res.json({ success: true, data: await finance.listPayments(req.query.invoiceId) }); }
  catch (e) { next(e); }
});
router.post('/payments', rbac.requireCompanyMember, rbac.requirePermission('finance', 'create'), async (req, res, next) => {
  try { const d = await finance.recordPayment(req.body || {}, req.firebaseUid); res.status(201).json({ success: true, data: d }); }
  catch (e) { next(e); }
});

module.exports = router;
