// Shared helpers for the public, unauthenticated forms (waitlist, contact and
// data deletion). They are deliberately dependency-free so the same validation
// and spam rules are used by every route and can be unit-tested without a
// database or a network.

const crypto = require('crypto');

function normalizeEmail(value) {
  return String(value || '').trim().toLowerCase();
}

function isValidEmail(value) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/i.test(value);
}

// A hidden honeypot field, or a form submitted faster than a human can type,
// is treated as automated. A future timestamp beyond a small clock-skew window
// is also rejected, otherwise a bot could bypass the timing check by sending
// tomorrow's date. Returns false for missing timing so older app clients that
// do not send `formStartedAt` keep working.
function isSpam(body, { minElapsedMs = 1500, maxClockSkewMs = 10 * 60 * 1000 } = {}) {
  const honeypot = String((body && (body.website || body.company)) || '').trim();
  if (honeypot) return true;
  const started = Number(body && body.formStartedAt);
  if (!Number.isFinite(started) || started <= 0) return false;
  const elapsed = Date.now() - started;
  if (elapsed < 0) return elapsed < -maxClockSkewMs;
  return elapsed < minElapsedMs;
}

function hashValue(value, length = 32) {
  return crypto.createHash('sha256').update(String(value)).digest('hex').slice(0, length);
}

// Storing a hash of the IP still lets us investigate abuse patterns while
// keeping the raw address out of the marketing collections.
function hashIp(req, length = 32) {
  const ip = (req && (req.ip || (req.connection && req.connection.remoteAddress))) || 'unknown';
  return hashValue(ip, length);
}

function randomToken(bytes = 32) {
  return crypto.randomBytes(bytes).toString('hex');
}

module.exports = {
  normalizeEmail,
  isValidEmail,
  isSpam,
  hashValue,
  hashIp,
  randomToken,
};
