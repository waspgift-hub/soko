const fs = require('fs');
const path = require('path');
const ROOT = path.join(__dirname, '..');
const head = fs.readFileSync(path.join(ROOT, 'lib', 'services', 'localization_service.dart'), 'utf8');
const lines = head.split('\n');

const swKeys = [
  "      'unlock_biometric': 'Fungua kwa alama ya vidole',",
  "      'unlock_with_pin': 'Fungua kwa namba ya siri',",
  "      'enter_pin_unlock_fallback': 'Au weka namba yako ya siri',",
  "      'biometric_locked_out': 'Alama imesitishwa. Tumia namba yako ya siri.',",
  "      'biometric_unavailable': 'Alama ya vidole haipatikani kwenye kifaa hiki.',",
  "      'biometric_not_recognised': 'Alama haijukubaliwa. Jaribu tena au tumia namba ya siri.',",
  "      'use_biometric_lock': 'Fungua kwa alama ya vidole',",
  "      'use_biometric_lock_sub': 'Badala ya kuingia kila siku kwa namba ya siri',",
];
const enKeys = [
  "      'unlock_biometric': 'Unlock with fingerprint',",
  "      'unlock_with_pin': 'Use PIN instead',",
  "      'enter_pin_unlock_fallback': 'Or enter your PIN',",
  "      'biometric_locked_out': 'Biometrics are locked. Use your PIN.',",
  "      'biometric_unavailable': 'No fingerprint is enrolled on this device.',",
  "      'biometric_not_recognised': 'Not recognised. Try again or use your PIN.',",
  "      'use_biometric_lock': 'Unlock with fingerprint',",
  "      'use_biometric_lock_sub': 'Sign in without typing a PIN each time',",
];

const swAnchor = lines.findIndex((l) => l.includes('enter_pin_unlock') && l.includes('Weka'));
const enAnchor = lines.findIndex((l) => l.includes('enter_pin_unlock') && l.includes('Enter your PIN'));

if (swAnchor < 0 || enAnchor < 0) {
  console.error('anchor not found');
  process.exit(1);
}

// Build the staged (HEAD + our keys) version as a Buffer. Never stringify through
// PowerShell — the file holds UTF-8 symbols that must survive byte-for-byte.
const out = lines.slice();
// Insert after the anchor, in reverse order so indices stay stable.
for (const k of [...swKeys].reverse()) out.splice(swAnchor + 1, 0, k);
// en anchor shifted by swKeys.length.
const enShifted = enAnchor + swKeys.length;
for (const k of [...enKeys].reverse()) out.splice(enShifted + 1, 0, k);

const staged = Buffer.from(out.join('\n'), 'utf8');

const full = fs.readFileSync(path.join(ROOT, 'lib', 'services', 'localization_service.dart'));
fs.writeFileSync(path.join(ROOT, 'lib', 'services', 'localization_service.dart'), staged);
const { execFileSync } = require('child_process');
try {
  execFileSync('git', ['add', '--', 'soko_langu/lib/services/localization_service.dart'], { cwd: path.join(ROOT, '..'), stdio: 'inherit' });
  console.log('staged OK');
} finally {
  fs.writeFileSync(path.join(ROOT, 'lib', 'services', 'localization_service.dart'), full);
}
console.log('restored working tree');

const diff = execFileSync('git', ['diff', '--cached', '--', 'soko_langu/lib/services/localization_service.dart'], {
  cwd: path.join(ROOT, '..'),
  maxBuffer: 64 * 1024 * 1024,
}).toString('utf8');
const added = diff.split('\n').filter((l) => l.startsWith('+') && !l.startsWith('+++'));
const removed = diff.split('\n').filter((l) => l.startsWith('-') && !l.startsWith('---'));
console.log(`staged diff: +${added.length} -${removed.length}`);
if (removed.length) {
  console.log('WARNING: lines removed:');
  removed.forEach((l) => console.log('  ' + l));
}
added.slice(0, 12).forEach((l) => console.log('  ' + l));
console.log('...');
