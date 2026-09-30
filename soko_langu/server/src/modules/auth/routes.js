const express = require('express');
const router = express.Router();
const { validate, schemas } = require('../../middleware/validation');
const { authLimiter, otpVerifyLimiter } = require('../../middleware/rateLimiter');
const { otpSendGuard } = require('../../middleware/otpGuard');
const { verifyAppCheck } = require('../../middleware/appCheck');
const { sendOtp, verifyOtp, sendEmailOtp, verifyEmailOtp, checkPhone, checkEmail, phoneLogin, resetPasswordByPhone, emailOtpLogin, otpSignIn } = require('./controller');

// Send routes are guarded by otpSendGuard (per-phone/email cooldown + quota +
// per-IP ceiling). The old shared per-IP OTP limiter is NOT applied here —
// one NAT would exhaust its whole budget for a campus of genuine users.
router.post('/send-otp', otpSendGuard('phone'), verifyAppCheck, validate(schemas.sendOtp), sendOtp);
router.post('/verify-otp', otpVerifyLimiter, validate(schemas.verifyOtp), verifyOtp);
router.post('/send-email-otp', otpSendGuard('email'), verifyAppCheck, sendEmailOtp);
router.post('/verify-email-otp', otpVerifyLimiter, verifyEmailOtp);
router.post('/check-phone', authLimiter, checkPhone);
router.post('/check-email', authLimiter, checkEmail);
router.post('/phone-login', otpVerifyLimiter, validate(schemas.phoneLogin), phoneLogin);
router.post('/email-otp-login', otpVerifyLimiter, emailOtpLogin);
router.post('/otp-sign-in', otpVerifyLimiter, otpSignIn);
router.post('/reset-password-by-phone', otpVerifyLimiter, validate(schemas.resetPasswordByPhone), resetPasswordByPhone);

module.exports = router;
