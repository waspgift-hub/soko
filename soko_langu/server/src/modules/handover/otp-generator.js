const crypto = require('crypto');

// Default security controls
const DEFAULTS = {
  otpLength: 6,
  maxAttempts: 5,
  defaultTtlMs: 30 * 60 * 1000, // 30 minutes
  charSet: '0123456789',
};

/**
 * Generate a cryptographically secure numeric OTP.
 * Uses crypto.randomInt for unbiased randomness.
 */
function generateOtp(length = DEFAULTS.otpLength) {
  const charSet = DEFAULTS.charSet;
  let otp = '';
  for (let i = 0; i < length; i++) {
    otp += charSet[crypto.randomInt(0, charSet.length)];
  }
  return otp;
}

/**
 * Hash a plaintext OTP with a random salt for storage.
 * Returns { hash, salt }.
 */
function hashOtp(otp, salt = crypto.randomBytes(16).toString('hex')) {
  const hash = crypto
    .createHash('sha256')
    .update(`${salt}:${otp}`)
    .digest('hex');
  return { hash, salt };
}

/**
 * Constant-time compare of a submitted OTP against a stored hash+salt.
 */
function verifyOtp(otp, storedHash, salt) {
  const candidate = crypto
    .createHash('sha256')
    .update(`${salt}:${otp}`)
    .digest('hex');
  const a = Buffer.from(candidate, 'hex');
  const b = Buffer.from(storedHash, 'hex');
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

/**
 * Generate a compact QR payload for visual/QR handover.
 * The QR encodes the order id + one-time handover token (challenge) so
 * that scanning it can populate the OTP/credentials exchange.
 */
function generateQrPayload({ orderId, orderNumber, token, expiresAt }) {
  return JSON.stringify({
    v: 1,
    t: 'sokovibe-handover',
    orderId,
    orderNumber,
    token,
    exp: new Date(expiresAt).toISOString(),
  });
}

module.exports = {
  DEFAULTS,
  generateOtp,
  hashOtp,
  verifyOtp,
  generateQrPayload,
};
