const crypto = require('crypto');
const logger = require('../shared/logger');

// ---------------------------------------------------------------------------
// Webhook Signature Verification
//
// WHY VERIFY?
// Without verification, anyone can send fake "payment completed" webhooks
// to your endpoint and get free products/services. Payment gateways sign
// every webhook with a shared secret. You verify the signature to prove
// the request actually came from the gateway.
//
// HOW IT WORKS:
// 1. Gateway sends: body + X-Webhook-Signature header (HMAC-SHA256 of body)
// 2. You compute: HMAC-SHA256(body, YOUR_SECRET)
// 3. Compare using timing-safe comparison (prevents timing attacks)
//
// Timing-safe comparison is critical — a normal `===` leaks information
// about the signature byte-by-byte through response time differences.
// ---------------------------------------------------------------------------

function verifyWebhookSignature(req) {
  const secret = process.env.WEBHOOK_SECRET;
  if (!secret) {
    logger.warn('WEBHOOK_SECRET not configured — skipping verification (DEV MODE)');
    return true;
  }

  const signature = req.headers['x-webhook-signature'] || req.headers['x-signature'];
  if (!signature) {
    logger.warn('Missing webhook signature header');
    return false;
  }

  const body = JSON.stringify(req.body);
  const expected = crypto
    .createHmac('sha256', secret)
    .update(body, 'utf8')
    .digest('hex');

  // Timing-safe comparison prevents attackers from guessing the signature
  // byte-by-byte by measuring response time differences
  try {
    return crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expected));
  } catch {
    return false;
  }
}

module.exports = { verifyWebhookSignature };
