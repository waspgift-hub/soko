// PII masking for logs and audit trails. Operational logs need enough signal
// to correlate incidents (last digits, domain) but must never carry full
// phone numbers or mailboxes — those belong only in the delivery call itself.
function maskPhone(phone) {
  const digits = String(phone || '').replace(/\D/g, '');
  if (digits.length < 4) return '***';
  return `***${digits.slice(-4)}`;
}

function maskEmail(email) {
  const s = String(email || '');
  const at = s.indexOf('@');
  if (at <= 1) return '***';
  return `${s[0]}***@${s.slice(at + 1)}`;
}

module.exports = { maskPhone, maskEmail };
