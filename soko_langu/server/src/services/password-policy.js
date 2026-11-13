// Central password policy (env-tunable, never scattered across handlers).
// Applies to every password the server SETS (phone-reset today, any future
// register/change endpoints). Firebase's own 6-char floor still applies at the
// provider, but this is the product bar and it is stricter.
const MIN_LENGTH = parseInt(process.env.PASSWORD_MIN_LENGTH || '8', 10);
const REQUIRE_LETTER = process.env.PASSWORD_REQUIRE_LETTER !== 'false';
const REQUIRE_DIGIT = process.env.PASSWORD_REQUIRE_DIGIT !== 'false';

// Returns { ok: true } or { ok: false, code } where code is a localisation key
// the app already knows how to render (auth_password_too_short / weak).
function validatePassword(pw) {
  const s = String(pw || '');
  if (s.length < MIN_LENGTH) return { ok: false, code: 'auth_password_too_short' };
  if (REQUIRE_LETTER && !/[A-Za-z]/.test(s)) return { ok: false, code: 'auth_password_weak' };
  if (REQUIRE_DIGIT && !/[0-9]/.test(s)) return { ok: false, code: 'auth_password_weak' };
  return { ok: true };
}

module.exports = { validatePassword, PASSWORD_MIN_LENGTH: MIN_LENGTH };
