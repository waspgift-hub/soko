const { Router } = require('express');
const { authenticate, requireActive } = require('../../middleware/auth');
const { validate } = require('../../middleware/validation');
const { otpVerifyLimiter, handoverLimiter } = require('../../middleware/rateLimiter');
const { z } = require('zod');
const handoverService = require('./handover-service');

const router = Router();

// Issue a fresh OTP credential (system/admin/SMS service)
router.post(
  '/:orderId/otp/issue',
  authenticate,
  requireActive,
  async (req, res) => {
    const result = await handoverService.issueOtp({
      orderId: req.params.orderId,
      issuedBy: req.user.id,
      userRole: req.user.role,
    });
    res.status(201).json({ success: true, data: result });
  }
);

// Verify OTP and complete the order atomically (handover).
//
// Two limiters, deliberately: `handoverLimiter` bounds how fast ONE buyer can
// hammer an order, and `otpVerifyLimiter` bounds the source. A 6-digit code is
// a 10^6 space with a 5-attempt cap on the credential, so guessing across many
// orders is the real threat — the per-source cap is what stops that.
router.post(
  '/:orderId/otp/verify',
  authenticate,
  requireActive,
  handoverLimiter,
  otpVerifyLimiter,
  validate({
    body: z.object({ otp: z.string().length(6) }),
  }),
  async (req, res) => {
    const result = await handoverService.verifyOtpAndComplete({
      orderId: req.params.orderId,
      submittedOtp: req.body.otp,
      verifiedBy: req.user.id,
      role: req.user.role,
    });
    res.json({ success: true, data: result });
  }
);

// Verify the QR handover token and complete the order atomically
router.post(
  '/:orderId/qr/verify',
  authenticate,
  requireActive,
  handoverLimiter,
  validate({
    body: z.object({ token: z.string().min(32).max(200) }),
  }),
  async (req, res) => {
    const result = await handoverService.verifyQrAndComplete({
      orderId: req.params.orderId,
      token: req.body.token,
      verifiedBy: req.user.id,
      role: req.user.role,
    });
    res.json({ success: true, data: result });
  }
);

module.exports = router;
