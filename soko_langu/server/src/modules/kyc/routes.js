const { Router } = require('express');
const { authenticate, authenticateAdmin } = require('../../middleware/auth');
const kycService = require('./kyc-service');
const { writeAudit, auditFromReq } = require('../../services/audit');

const router = Router();

// ---------------------------------------------------------------------------
// App-facing (Firebase-authenticated, owner-only)
// ---------------------------------------------------------------------------

// Status. Owner or admin may read.
router.get('/status/:userId', authenticate, async (req, res) => {
  try {
    const target = req.params.userId;
    const isAdmin = ['admin', 'super_admin'].includes(req.user.role);
    if (req.firebaseUid !== target && !isAdmin) {
      return res.status(403).json({ success: false, error: { code: 'FORBIDDEN', message: 'Not authorized to view this KYC' } });
    }
    const kyc = await kycService.getStatus({ userId: target });
    res.json({ success: true, data: { kyc } });
  } catch (e) {
    res.status(500).json({ success: false, error: { code: 'KYC_STATUS_FAILED', message: e.message } });
  }
});

// Submit/resubmit. The authenticated caller is always the subject.
router.post('/submit', authenticate, async (req, res) => {
  try {
    const { fullName, idType, idNumber, idImageUrl, selfieUrl } = req.body || {};
    const result = await kycService.submitKyc({
      userId: req.firebaseUid,
      fullName,
      idType,
      idNumber,
      idImageUrl,
      selfieUrl,
    });
    res.json({ success: true, data: { approved: result.approved, reason: result.reason, message: result.message } });
  } catch (e) {
    const status = e.status || 500;
    const code = e.code || 'KYC_SUBMIT_FAILED';
    res.status(status).json({ success: false, error: { code, message: e.message } });
  }
});

// ---------------------------------------------------------------------------
// Admin panel (x-admin-secret gate, matching v1 admin router conventions).
// The Flutter admin panel is NOT wired here yet — it stays on legacy
// /api/admin/kyc/* until it adopts x-admin-secret auth (OWNERSHIP_MAP §6.8).
// ---------------------------------------------------------------------------

const admin = Router();
admin.use(authenticateAdmin);

// List all applications (newest first). Optional ?status= filter.
admin.get('/applications', async (req, res) => {
  try {
    const page = Math.max(1, parseInt(req.query.page || '1', 10));
    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit || '50', 10)));
    const result = await kycService.listApplications({ status: req.query.status, page, limit });
    res.json({ success: true, data: result });
  } catch (e) {
    res.status(500).json({ success: false, error: { code: 'KYC_LIST_FAILED', message: e.message } });
  }
});

// Approve / reject an application.
admin.post('/:userId/review', async (req, res) => {
  try {
    const { approve, notes } = req.body || {};
    if (approve == null || typeof approve !== 'boolean') {
      return res.status(400).json({ success: false, error: { code: 'VALIDATION', message: 'approve (boolean) is required' } });
    }
    const row = await kycService.reviewKyc({ userId: req.params.userId, approve, notes });
    await writeAudit({
      ...auditFromReq(req),
      action: `kyc.${approve ? 'approved' : 'rejected'}`,
      entityType: 'kyc_application',
      entityId: row.id,
      oldState: { status: row.approved ? 'approved' : 'rejected' },
      newState: { status: row.status, notes },
    }).catch(() => {});
    res.json({ success: true, data: kycService.toPublic(row) });
  } catch (e) {
    const status = e.status || 500;
    const code = e.code || 'KYC_REVIEW_FAILED';
    res.status(status).json({ success: false, error: { code, message: e.message } });
  }
});

// Revoke.
admin.post('/:userId/revoke', async (req, res) => {
  try {
    const row = await kycService.revokeKyc({ userId: req.params.userId, reason: req.body?.reason });
    await writeAudit({
      ...auditFromReq(req),
      action: 'kyc.revoked',
      entityType: 'kyc_application',
      entityId: row.id,
      newState: { status: 'revoked', reason: req.body?.reason },
    }).catch(() => {});
    res.json({ success: true, data: kycService.toPublic(row) });
  } catch (e) {
    const status = e.status || 500;
    const code = e.code || 'KYC_REVOKE_FAILED';
    res.status(status).json({ success: false, error: { code, message: e.message } });
  }
});

// Delete.
admin.delete('/:userId', async (req, res) => {
  try {
    const result = await kycService.deleteKyc({ userId: req.params.userId });
    await writeAudit({
      ...auditFromReq(req),
      action: 'kyc.deleted',
      entityType: 'kyc_application',
      newState: { deleted: result.deleted },
    }).catch(() => {});
    res.json({ success: true, data: result });
  } catch (e) {
    const status = e.status || 500;
    const code = e.code || 'KYC_DELETE_FAILED';
    res.status(status).json({ success: false, error: { code, message: e.message } });
  }
});

router.use('/admin', admin);

module.exports = router;