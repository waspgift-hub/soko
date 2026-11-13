// TOTP (RFC 6238) helper for admin MFA. Uses Node's built-in crypto only
// (no extra dependencies). Secrets are base32-encoded (RFC 4648, no padding).
'use strict';

const crypto = require('crypto');

const BASE32_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

function base32Encode(buf) {
  let bits = 0;
  let value = 0;
  let out = '';
  for (let i = 0; i < buf.length; i++) {
    value = (value << 8) | buf[i];
    bits += 8;
    while (bits >= 5) {
      out += BASE32_ALPHABET[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) {
    out += BASE32_ALPHABET[(value << (5 - bits)) & 31];
  }
  return out;
}

function base32Decode(str) {
  const s = String(str || '').toUpperCase().replace(/=+$/, '').replace(/\s+/g, '');
  let bits = 0;
  let value = 0;
  const out = [];
  for (let i = 0; i < s.length; i++) {
    const idx = BASE32_ALPHABET.indexOf(s[i]);
    if (idx < 0) throw new Error('INVALID_BASE32');
    value = (value << 5) | idx;
    bits += 5;
    if (bits >= 8) {
      out.push((value >>> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  return Buffer.from(out);
}

function generateSecret(bytes = 20) {
  return base32Encode(crypto.randomBytes(bytes));
}

function hotp(secretBase32, counter, digits = 6) {
  const key = base32Decode(secretBase32);
  const buf = Buffer.alloc(8);
  // counter as 64-bit big-endian
  let c = counter;
  for (let i = 7; i >= 0; i--) {
    buf[i] = c & 0xff;
    c = Math.floor(c / 256);
  }
  const hmac = crypto.createHmac('sha1', key).update(buf).digest();
  const offset = hmac[hmac.length - 1] & 0x0f;
  const code = ((hmac[offset] & 0x7f) << 24) |
    ((hmac[offset + 1] & 0xff) << 16) |
    ((hmac[offset + 2] & 0xff) << 8) |
    (hmac[offset + 3] & 0xff);
  const otp = (code % Math.pow(10, digits)).toString().padStart(digits, '0');
  return otp;
}

function totp(secretBase32, nowMs = Date.now(), step = 30, digits = 6, window = 1) {
  const counter = Math.floor(nowMs / 1000 / step);
  const codes = [];
  for (let w = -window; w <= window; w++) {
    codes.push(hotp(secretBase32, counter + w, digits));
  }
  return codes;
}

function verify(secretBase32, code, nowMs = Date.now(), step = 30, digits = 6, window = 1) {
  const input = String(code || '').trim();
  if (!/^\d{6}$/.test(input)) return false;
  const accepted = totp(secretBase32, nowMs, step, digits, window);
  // Constant-time-ish comparison
  return accepted.some((c) => {
    if (c.length !== input.length) return false;
    let diff = 0;
    for (let i = 0; i < c.length; i++) diff |= c.charCodeAt(i) ^ input.charCodeAt(i);
    return diff === 0;
  });
}

function otpauthUri({ secret, account, issuer = 'Soko Vibe' }) {
  const label = encodeURIComponent(`${issuer}:${account}`);
  const params = new URLSearchParams({
    secret,
    issuer,
    algorithm: 'SHA1',
    digits: '6',
    period: '30',
  });
  return `otpauth://totp/${label}?${params.toString()}`;
}

module.exports = {
  generateSecret,
  base32Encode,
  base32Decode,
  hotp,
  totp,
  verify,
  otpauthUri,
};
