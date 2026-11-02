'use strict';
const { Router } = require('express');
const { authenticate } = require('../../middleware/auth');
const { loadCompanyMembership } = require('./membership');
const rbac = require('./rbac');
const projects = require('./projects');

const router = Router();
router.use(authenticate);
router.use(loadCompanyMembership);

router.get('/projects', rbac.requireCompanyMember, rbac.requirePermission('projects', 'read'), async (req, res, next) => {
  try { res.json({ success: true, data: await projects.listProjects({ legalEntityId: req.query.legalEntityId, department: req.query.department, status: req.query.status }) }); }
  catch (e) { next(e); }
});
router.post('/projects', rbac.requireCompanyMember, rbac.requirePermission('projects', 'create'), async (req, res, next) => {
  try { const d = await projects.createProject(req.body || {}, req.firebaseUid); res.status(201).json({ success: true, data: d }); }
  catch (e) { next(e); }
});
router.get('/projects/:id', rbac.requireCompanyMember, rbac.requirePermission('projects', 'read'), async (req, res, next) => {
  try { const d = await projects.getProject(req.params.id); if (!d) return res.status(404).json({ success: false, code: 'NOT_FOUND' }); res.json({ success: true, data: d }); }
  catch (e) { next(e); }
});
router.put('/projects/:id', rbac.requireCompanyMember, rbac.requirePermission('projects', 'edit'), async (req, res, next) => {
  try { res.json({ success: true, data: await projects.updateProject(req.params.id, req.body || {}, req.firebaseUid) }); }
  catch (e) { next(e); }
});
router.get('/projects/:id/milestones', rbac.requireCompanyMember, rbac.requirePermission('projects', 'read'), async (req, res, next) => {
  try { res.json({ success: true, data: await projects.listMilestones(req.params.id) }); }
  catch (e) { next(e); }
});
router.post('/milestones', rbac.requireCompanyMember, rbac.requirePermission('projects', 'create'), async (req, res, next) => {
  try { const d = await projects.createMilestone(req.body || {}, req.firebaseUid); res.status(201).json({ success: true, data: d }); }
  catch (e) { next(e); }
});
router.post('/milestones/:id/accept', rbac.requireCompanyMember, rbac.requirePermission('projects', 'approve'), async (req, res, next) => {
  try { res.json({ success: true, data: await projects.acceptMilestone(req.params.id, req.firebaseUid) }); }
  catch (e) { next(e); }
});
router.get('/tasks', rbac.requireCompanyMember, rbac.requirePermission('tasks', 'read'), async (req, res, next) => {
  try { res.json({ success: true, data: await projects.listTasks({ projectId: req.query.projectId, ownerUid: req.query.ownerUid, status: req.query.status }) }); }
  catch (e) { next(e); }
});
router.post('/tasks', rbac.requireCompanyMember, rbac.requirePermission('tasks', 'create'), async (req, res, next) => {
  try { const d = await projects.createTask(req.body || {}, req.firebaseUid); res.status(201).json({ success: true, data: d }); }
  catch (e) { next(e); }
});
router.post('/tasks/:id/transition', rbac.requireCompanyMember, rbac.requirePermission('tasks', 'edit'), async (req, res, next) => {
  try { const d = await projects.transitionTask(req.params.id, req.body?.status, req.firebaseUid, req.body?.reason || ''); res.json({ success: true, data: d }); }
  catch (e) { next(e); }
});

module.exports = router;
PY