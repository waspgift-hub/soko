const { Router } = require('express');
const { authenticate, requireActive } = require('../../middleware/auth');
const { validate } = require('../../middleware/validation');
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
      issuedBy: req.user.uid,
    });
    res.status(201).json({ success: true, data: result });
  }
);

// Verify OTP and complete the order atomically (handover)
router.post(
  '/:orderId/otp/verify',
  authenticate,
  requireActive,
  validate({
    body: z.object({ otp: z.string().length(6) }),
  }),
  async (req, res) => {
    const result = await handoverService.verifyOtpAndComplete({
      orderId: req.params.orderId,
      submittedOtp: req.body.otp,
      verifiedBy: req.user.uid,
    });
    res.json({ success: true, data: result });
  }
);

module.exports = router;
