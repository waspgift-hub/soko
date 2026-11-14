const crypto = require('crypto');
const { getFirebaseFirestore } = require('../../config/firebase');

const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
const CODE_RE = /^[A-Z2-7]{4}-[A-Z2-7]{4}$/;

function normalizeCode(code) {
  return String(code || '').trim().toUpperCase().replace(/\s+/g, '');
}

function hashCode(code) {
  return crypto.createHash('sha256').update(normalizeCode(code)).digest('hex');
}

function hashesEqual(a, b) {
  const left = Buffer.from(String(a));
  const right = Buffer.from(String(b));
  return left.length === right.length && crypto.timingSafeEqual(left, right);
}

function generateCode() {
  const bytes = crypto.randomBytes(8);
  let raw = '';
  for (let i = 0; i < 8; i += 1) raw += ALPHABET[bytes[i] % ALPHABET.length];
  return `${raw.slice(0, 4)}-${raw.slice(4)}`;
}

function httpError(status, message) {
  const err = new Error(message);
  err.status = status;
  return err;
}

async function issueRecoveryCodes(uid) {
  const db = getFirebaseFirestore();
  if (!db) throw httpError(503, 'AUTH_NOT_CONFIGURED');
  const codes = Array.from({ length: 10 }, generateCode);
  const now = new Date();
  await db.collection('mfaRecovery').doc(uid).set({
    uid,
    codes: codes.map((code) => ({ hash: hashCode(code), usedAt: null })),
    generatedAt: now,
    updatedAt: now,
  });
  return codes;
}

async function consumeRecoveryCode(uid, code) {
  const db = getFirebaseFirestore();
  if (!db) throw httpError(503, 'AUTH_NOT_CONFIGURED');
  const normalized = normalizeCode(code);
  if (!CODE_RE.test(normalized)) return { ok: false, reason: 'INVALID_FORMAT' };
  const target = hashCode(normalized);
  const ref = db.collection('mfaRecovery').doc(uid);
  return db.runTransaction(async (t) => {
    const snap = await t.get(ref);
    if (!snap.exists) return { ok: false, reason: 'NOT_ENROLLED' };
    const codes = Array.isArray(snap.data().codes) ? snap.data().codes.slice() : [];
    const idx = codes.findIndex((row) => row && !row.usedAt && hashesEqual(row.hash, target));
    if (idx < 0) return { ok: false, reason: 'INVALID_OR_USED' };
    codes[idx] = { hash: codes[idx].hash, usedAt: new Date().toISOString() };
    t.update(ref, { codes, updatedAt: new Date() });
    return { ok: true };
  });
}

module.exports = {
  issueRecoveryCodes,
  consumeRecoveryCode,
  hashCode,
  normalizeCode,
  generateCode,
  CODE_RE,
};
