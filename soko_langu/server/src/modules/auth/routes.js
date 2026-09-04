const express = require('express');
const router = express.Router();
const { validate, schemas } = require('../../middleware/validation');
const { authLimiter, otpRequestLimiter, otpVerifyLimiter } = require('../../middleware/rateLimiter');
const { sendOtp, verifyOtp, sendEmailOtp, verifyEmailOtp, checkPhone, checkEmail, phoneLogin, resetPasswordByPhone } = require('./controller');

router.post('/send-otp', otpRequestLimiter, validate(schemas.sendOtp), sendOtp);
router.post('/verify-otp', otpVerifyLimiter, validate(schemas.verifyOtp), verifyOtp);
router.post('/send-email-otp', otpRequestLimiter, sendEmailOtp);
router.post('/verify-email-otp', otpVerifyLimiter, verifyEmailOtp);
router.post('/check-phone', authLimiter, checkPhone);
router.post('/check-email', authLimiter, checkEmail);
router.post('/phone-login', otpVerifyLimiter, validate(schemas.phoneLogin), phoneLogin);
router.post('/reset-password-by-phone', otpVerifyLimiter, validate(schemas.resetPasswordByPhone), resetPasswordByPhone);

module.exports = router;
