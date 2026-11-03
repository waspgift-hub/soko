/**
 * Money-safe coercion helpers.
 *
 * All TZS amounts in v2 are integer BigInt (minor units). Incoming values come
 * from JSON bodies / provider payloads as numbers or strings, and the DB stores
 * BigInt. Converting with BigInt(Number(x)) after rounding keeps the equality
 * checks honest without ever introducing floating-point arithmetic into a
 * stored amount.
 */

function toBigIntSafe(value) {
  if (typeof value === 'bigint') return value;
  if (value === null || value === undefined || value === '') return 0n;
  const n = Number(value);
  if (!Number.isFinite(n)) return 0n;
  return BigInt(Math.round(n));
}

function sameAmount(a, b) {
  return toBigIntSafe(a) === toBigIntSafe(b);
}

module.exports = { toBigIntSafe, sameAmount };