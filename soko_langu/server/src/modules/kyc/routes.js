const { Router } = require('express');
const { authenticate, authenticateAdmin } = require('../../middleware/auth');
const kycService = require('./kyc-service');
const { writeAudit, auditFromReq } = require('../../services/audit');
const { otpSendGuard, otpVerifyGuard, releaseOtpClaim } = require('../../middleware/otpGuard');
const { presignKycDocument, DOCUMENT_IDS } = require('../media/kyc-documents');

const router = Router();

// Answers a send attempt honestly. Every KYC OTP send route used to reply
// { success: true } regardless of whether the SMS/mail actually went out, so the
// app told the seller to wait for a code that was never delivered. A failed
// delivery now also gives back the guard's cooldown and quota slot, because the
// user is about to hit "resend" and must not be punished for our gateway fault.
async function respondToOtpSend(res, req, result, errorCode) {
  if (!result || !result.sent) {
    await releaseOtpClaim(req);
    return res.status(502).json({
      success: false,
      error: { code: errorCode, message: 'OTP haukuweza kutumwa. Jaribu tena.' },
    });
  }
  return res.json({ success: true, data: result });
}

// ---------------------------------------------------------------------------
// App-facing (Firebase-authenticated, owner-only)
// ---------------------------------------------------------------------------

// Temporary read URL for the CALLER'S OWN KYC document.
//
// There is deliberately no user id in the path: the row is looked up by the
// verified session's uid, so there is no identifier a caller could swap to reach
// another seller's passport. `expectOwnerUid` re-checks ownership inside the
// resolver as defence in depth.
//
// Without this the seller cannot see the document they just submitted, because
// the stored column is a private key and has no public URL.
router.get('/documents/:documentId/read-url', authenticate, async (req, res) => {
  const uid = req.user.firebaseUid;
  try {
    const result = await presignKycDocument({
      userId: uid,
      documentId: req.params.documentId,
      expectOwnerUid: uid,
    });
    res.json({ success: true, data: result });
  } catch (e) {
    res.status(e.status || 500).json({
      success: false,
      error: { code: e.code || 'KYC_DOCUMENT_READ_FAILED' },
    });
  }
});

// Send a phone OTP (SMS). body: { value }   -> { success, sent, expiresInSec }
router.post('/verify/phone/send', authenticate, otpSendGuard('phone', 'value'), async (req, res) => {
  try {
    const result = await kycService.sendContactOtp({
      userId: req.firebaseUid,
      channel: 'phone',
      value: req.body?.value,
    });
    return respondToOtpSend(res, req, result, 'KYC_PHONE_OTP_SEND_FAILED');
  } catch (e) {
    await releaseOtpClaim(req);
    res.status(e.status || 400).json({ success: false, error: { code: e.code || 'KYC_PHONE_OTP_SEND_FAILED', message: e.message } });
  }
});

// Verify a phone OTP. body: { value, otp }   -> { success, verified }
router.post('/verify/phone/confirm', authenticate, otpVerifyGuard('phone', 'value'), async (req, res) => {
  try {
    const result = await kycService.verifyContactOtp({
      userId: req.firebaseUid,
      channel: 'phone',
      value: req.body?.value,
      otp: req.body?.otp,
    });
    res.json({ success: true, data: result });
  } catch (e) {
    res.status(e.status || 400).json({ success: false, error: { code: e.code || 'KYC_PHONE_OTP_INVALID', message: e.message } });
  }
});

// Send an email OTP. body: { value }         -> { success, sent, expiresInSec }
router.post('/verify/email/send', authenticate, otpSendGuard('email', 'value'), async (req, res) => {
  try {
    const result = await kycService.sendContactOtp({
      userId: req.firebaseUid,
      channel: 'email',
      value: req.body?.value,
    });
    return respondToOtpSend(res, req, result, 'KYC_EMAIL_OTP_SEND_FAILED');
  } catch (e) {
    await releaseOtpClaim(req);
    res.status(e.status || 400).json({ success: false, error: { code: e.code || 'KYC_EMAIL_OTP_SEND_FAILED', message: e.message } });
  }
});

// Verify an email OTP. body: { value, otp }  -> { success, verified }
router.post('/verify/email/confirm', authenticate, otpVerifyGuard('email', 'value'), async (req, res) => {
  try {
    const result = await kycService.verifyContactOtp({
      userId: req.firebaseUid,
      channel: 'email',
      value: req.body?.value,
      otp: req.body?.otp,
    });
    res.json({ success: true, data: result });
  } catch (e) {
    res.status(e.status || 400).json({ success: false, error: { code: e.code || 'KYC_EMAIL_OTP_INVALID', message: e.message } });
  }
});

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

// Send a KYC contact OTP (phone => SMS, email => mailer). `channel` is
// 'phone' or 'email'; `value` is the raw contact to verify.
router.post('/verify/phone', authenticate, otpSendGuard('phone', 'value'), async (req, res) => {
  try {
    const result = await kycService.sendContactOtp({
      userId: req.firebaseUid,
      channel: 'phone',
      value: req.body?.value,
    });
    return respondToOtpSend(res, req, result, 'KYC_OTP_SEND_FAILED');
  } catch (e) {
    await releaseOtpClaim(req);
    res.status(e.status || 400).json({ success: false, error: { code: e.code || 'KYC_OTP_SEND_FAILED', message: e.message } });
  }
});

router.post('/verify/email', authenticate, otpSendGuard('email', 'value'), async (req, res) => {
  try {
    const result = await kycService.sendContactOtp({
      userId: req.firebaseUid,
      channel: 'email',
      value: req.body?.value,
    });
    return respondToOtpSend(res, req, result, 'KYC_OTP_SEND_FAILED');
  } catch (e) {
    await releaseOtpClaim(req);
    res.status(e.status || 400).json({ success: false, error: { code: e.code || 'KYC_OTP_SEND_FAILED', message: e.message } });
  }
});

// Submit/resubmit. The authenticated caller is always the subject.
router.post('/submit', authenticate, async (req, res) => {
  try {
    const {
      fullName, firstName, middleName, lastName,
      idType, idNumber, idImageUrl, selfieUrl,
      dateOfBirth, address, phone, email, shopVideoUrl,
    } = req.body || {};
    const result = await kycService.submitKyc({
      userId: req.firebaseUid,
      fullName,
      firstName,
      middleName,
      lastName,
      idType,
      idNumber,
      idImageUrl,
      selfieUrl,
      dateOfBirth,
      address,
      phone,
      email,
      shopVideoUrl,
    });
    res.json({ success: true, data: { approved: result.approved, reason: result.reason, message: result.message } });
  } catch (e) {
    const status = e.status || 500;
    const code = e.code || 'KYC_SUBMIT_FAILED';
    res.status(status).json({ success: false, error: { code, message: e.message } });
  }
});

// ---------------------------------------------------------------------------
// One-time verification fee (TSh 15,000) — ClickPesa collection.
// ---------------------------------------------------------------------------

// Whether the caller's fee is settled (polled by the app after a USSD push).
router.get('/fee/status', authenticate, async (req, res) => {
  try {
    const fee = await kycService.getKycFeeStatus({ userId: req.firebaseUid });
    res.json({ success: true, data: fee });
  } catch (e) {
    res.status(500).json({ success: false, error: { code: 'KYC_FEE_STATUS_FAILED', message: e.message } });
  }
});

// Start a fee collection. `paymentMethod` is 'ussd_push' (default) or 'billpay'.
router.post('/fee/initiate', authenticate, async (req, res) => {
  try {
    const { phone, paymentMethod } = req.body || {};
    const result = await kycService.initiateKycFee({
      userId: req.firebaseUid,
      phone,
      paymentMethod,
    });
    res.json({ success: true, data: result });
  } catch (e) {
    const status = e.status || 500;
    const code = e.code || 'KYC_FEE_INITIATE_FAILED';
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