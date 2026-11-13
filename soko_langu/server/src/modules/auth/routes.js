const express = require('express');
const router = express.Router();
const { validate, schemas } = require('../../middleware/validation');
const { authLimiter, otpRequestLimiter, otpVerifyLimiter, loginLimiter } = require('../../middleware/rateLimiter');
const { otpSendGuard } = require('../../middleware/otpGuard');
const { verifyAppCheck } = require('../../middleware/appCheck');
const { authenticate } = require('../../middleware/auth');
const { sendOtp, verifyOtp, sendEmailOtp, verifyEmailOtp, checkPhone, checkEmail, phoneLogin, resetPasswordByPhone, emailOtpLogin, otpSignIn, logoutAll } = require('./controller');

// Send routes are guarded by otpSendGuard (per-phone/email cooldown + quota +
// per-IP ceiling) with the loose otpRequestLimiter as a global backstop. The
// old shared per-IP-only OTP limiter is NOT the primary guard — one NAT would
// exhaust its whole budget for a campus of genuine users.
router.post('/send-otp', otpRequestLimiter, otpSendGuard('phone'), verifyAppCheck, validate(schemas.sendOtp), sendOtp);
router.post('/verify-otp', otpVerifyLimiter, validate(schemas.verifyOtp), verifyOtp);
router.post('/send-email-otp', otpRequestLimiter, otpSendGuard('email'), verifyAppCheck, validate(schemas.sendEmailOtp), sendEmailOtp);
router.post('/verify-email-otp', otpVerifyLimiter, validate(schemas.verifyEmailOtp), verifyEmailOtp);
// Existence probes keep the shared IP bucket AND a per-target ceiling inside
// the handler (registration needs them; brute-force enumeration must be dear).
router.post('/check-phone', authLimiter, checkPhone);
router.post('/check-email', authLimiter, checkEmail);
router.post('/phone-login', otpVerifyLimiter, validate(schemas.phoneLogin), phoneLogin);
router.post('/email-otp-login', otpVerifyLimiter, emailOtpLogin);
// Admin sign-in is rare and high-value: the tight per-IP loginLimiter belongs
// here, not on user login routes where one carrier NAT would starve genuine
// users (those are bounded by otpVerifyLimiter plus the per-code lockout).
router.post('/otp-sign-in', loginLimiter, otpVerifyLimiter, otpSignIn);
router.post('/reset-password-by-phone', otpVerifyLimiter, validate(schemas.resetPasswordByPhone), resetPasswordByPhone);
// Revokes every session for the caller (logout from all devices). The client
// signs out locally right after.
router.post('/logout-all', authenticate, logoutAll);

module.exports = router;
