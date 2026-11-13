'use strict';

const { Router } = require('express');
const { authenticate } = require('../../middleware/auth');
const { loadCompanyMembership } = require('./membership');
const rbac = require('./rbac');
const audit = require('./audit');
const { getFirebaseFirestore } = require('../../config/firebase');

const router = Router();

const MEMBERSHIPS = 'company_memberships';
const LEGAL_ENTITIES = 'company_legal_entities';
const SETTINGS = 'company_settings';

// All company routes require Firebase auth + membership load.
router.use(authenticate);
router.use(loadCompanyMembership);

// GET /api/company/me — current membership (or null)
router.get('/me', (req, res) => {
  res.json({ success: true, data: req.companyMembership || null });
});

// GET /api/company/overview — founder command center summary
router.get('/overview', rbac.requireCompanyMember, async (req, res, next) => {
  try {
    const overview = require('./overview');
    const data = await overview.getOverview();
    res.json({ success: true, data });
  } catch (e) {
    next(e);
  }
});

// POST /api/company/bootstrap — create the first founder membership.
// Allowed only when no founder exists yet. Idempotent for the same uid.
router.post('/bootstrap', async (req, res, next) => {
  try {
    const db = getFirebaseFirestore();
    if (!db) return res.status(503).json({ success: false, code: 'FIRESTORE_UNAVAILABLE' });

    const existing = await db.collection(MEMBERSHIPS).where('role', '==', 'founder').limit(1).get();
    const mine = req.companyMembership;

    if (existing.size > 0 && (!mine || mine.role !== 'founder')) {
      return res.status(403).json({ success: false, code: 'FOUNDER_EXISTS', error: 'A founder already exists' });
    }

    const membership = await require('./membership').upsertMembership(req.firebaseUid, {
      role: 'founder',
      status: 'active',
      legal_entity_ids: [],
      mfa_verified: false,
    });

    await audit.logAuditEvent({
      actorUid: req.firebaseUid,
      action: 'company.bootstrap',
      targetType: 'membership',
      targetId: req.firebaseUid,
      reason: 'Initial founder bootstrap',
    });

    res.status(201).json({ success: true, data: membership });
  } catch (e) {
    next(e);
  }
});

// GET /api/company/legal-entities
router.get('/legal-entities', rbac.requireCompanyMember, rbac.requirePermission('legal_entities', 'read'), async (req, res, next) => {
  try {
    const db = getFirebaseFirestore();
    if (!db) return res.status(503).json({ success: false, code: 'FIRESTORE_UNAVAILABLE' });
    const snap = await db.collection(LEGAL_ENTITIES).orderBy('created_at', 'desc').limit(100).get();
    res.json({ success: true, data: snap.docs.map((d) => ({ id: d.id, ...d.data() })) });
  } catch (e) {
    next(e);
  }
});

// POST /api/company/legal-entities
router.post('/legal-entities', rbac.requireCompanyMember, rbac.requirePermission('legal_entities', 'create'), async (req, res, next) => {
  try {
    const db = getFirebaseFirestore();
    if (!db) return res.status(503).json({ success: false, code: 'FIRESTORE_UNAVAILABLE' });
    const body = req.body || {};
    if (!body.name || typeof body.name !== 'string') {
      return res.status(400).json({ success: false, code: 'INVALID_NAME', error: 'name is required' });
    }
    const now = new Date().toISOString();
    const doc = {
      name: body.name.trim(),
      registration_number: body.registrationNumber || '',
      tax_id: body.taxId || '',
      address: body.address || '',
      fiscal_year_start: body.fiscalYearStart || '01-01',
      timezone: body.timezone || 'Africa/Dar_es_Salaam',
      currency: body.currency || 'TZS',
      created_by: req.firebaseUid,
      created_at: now,
      updated_at: now,
    };
    const ref = await db.collection(LEGAL_ENTITIES).add(doc);
    await audit.logAuditEvent({
      actorUid: req.firebaseUid,
      action: 'legal_entity.create',
      targetType: 'legal_entity',
      targetId: ref.id,
      reason: body.reason || '',
      legalEntityId: ref.id,
    });
    res.status(201).json({ success: true, data: { id: ref.id, ...doc } });
  } catch (e) {
    next(e);
  }
});

// GET /api/company/audit
router.get('/audit', rbac.requireCompanyMember, rbac.requirePermission('audit', 'read'), async (req, res, next) => {
  try {
    const events = await audit.listAuditEvents({
      limit: Number(req.query.limit) || 50,
      actorUid: req.query.actorUid || '',
      targetType: req.query.targetType || '',
      legalEntityId: req.query.legalEntityId || '',
    });
    res.json({ success: true, data: events });
  } catch (e) {
    next(e);
  }
});

// GET /api/company/settings
router.get('/settings', rbac.requireCompanyMember, async (req, res, next) => {
  try {
    const db = getFirebaseFirestore();
    if (!db) return res.status(503).json({ success: false, code: 'FIRESTORE_UNAVAILABLE' });
    const snap = await db.collection(SETTINGS).doc('global').get();
    res.json({ success: true, data: snap.exists ? snap.data() : {} });
  } catch (e) {
    next(e);
  }
});

// PUT /api/company/settings
router.put('/settings', rbac.requireCompanyMember, rbac.requirePermission('settings', 'configure'), async (req, res, next) => {
  try {
    const db = getFirebaseFirestore();
    if (!db) return res.status(503).json({ success: false, code: 'FIRESTORE_UNAVAILABLE' });
    const patch = req.body || {};
    const now = new Date().toISOString();
    await db.collection(SETTINGS).doc('global').set({ ...patch, updated_at: now, updated_by: req.firebaseUid }, { merge: true });
    await audit.logAuditEvent({
      actorUid: req.firebaseUid,
      action: 'settings.update',
      targetType: 'settings',
      targetId: 'global',
      reason: patch.reason || '',
    });
    const snap = await db.collection(SETTINGS).doc('global').get();
    res.json({ success: true, data: snap.data() });
  } catch (e) {
    next(e);
  }
});

module.exports = router;
module.exports.rbac = rbac;
module.exports.audit = audit;
module.exports.membership = require('./membership');
