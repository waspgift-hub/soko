const crypto = require('crypto');

// Constant-time admin-secret check. Every admin route compares against this
// instead of a plain `===` so an attacker measuring response timing cannot
// guess the secret byte-by-byte.
function verifyAdminSecret(secret) {
  const expected = process.env.ADMIN_SECRET;
  if (!expected || !secret) return false;
  const a = Buffer.from(String(secret));
  const b = Buffer.from(String(expected));
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

module.exports = { verifyAdminSecret };