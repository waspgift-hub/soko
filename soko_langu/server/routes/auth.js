const express = require('express');

module.exports = function (deps) {
  const router = express.Router();
  const ctrl = require('../controllers/authController')(deps);
  const { otpPhoneRateLimit, otpVerifyRateLimit } = require('../middlewares/auth')(deps);

  router.post('/send-otp', otpPhoneRateLimit, ctrl.sendOtp);
  router.post('/verify-otp', otpVerifyRateLimit, ctrl.verifyOtp);
  router.post('/send-email-otp', ctrl.sendEmailOtp);
  router.post('/verify-email-otp', otpVerifyRateLimit, ctrl.verifyEmailOtp);
  router.post('/check-phone', ctrl.checkPhone);
  router.post('/check-email', ctrl.checkEmail);
  router.post('/reset-password-by-phone', otpVerifyRateLimit, ctrl.resetPasswordByPhone);

  return { router, phoneLogin: ctrl.phoneLogin };
};
