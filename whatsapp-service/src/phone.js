const config = require('./config');

// Cloud API wants digits only (no "+"). Accepts +255..., 255..., 0XXXXXXXXX
// and bare 9-digit local numbers, then returns the international form.
function normalizePhone(raw, countryCode = config.defaultCountryCode) {
  if (raw === undefined || raw === null) return null;
  let digits = String(raw).replace(/[\s\-()]/g, '');
  if (digits.startsWith('+')) digits = digits.slice(1);
  if (!/^\d+$/.test(digits)) return null;
  if (digits.startsWith('00')) digits = digits.slice(2);
  if (digits.startsWith('0')) digits = countryCode + digits.slice(1);
  else if (digits.length === 9) digits = countryCode + digits;
  if (digits.length < 9 || digits.length > 15) return null;
  return digits;
}

function maskPhone(phone) {
  const s = String(phone || '');
  return s.length <= 4 ? '****' : `${'*'.repeat(s.length - 4)}${s.slice(-4)}`;
}

module.exports = { normalizePhone, maskPhone };
