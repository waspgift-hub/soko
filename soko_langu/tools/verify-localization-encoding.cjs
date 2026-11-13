// Checks whether localization_service.dart still holds valid UTF-8.
//
// PowerShell's Out-File/Get-Content round-trip re-encodes UTF-8 bytes as if they
// were ANSI, which silently turns every currency symbol into mojibake. This file
// is generated text with TSh and euro signs in it, so it must never be written
// through PowerShell.
const fs = require('fs');
const path = require('path');

const file = path.join(__dirname, '..', 'lib', 'services', 'localization_service.dart');
const buf = fs.readFileSync(file);
const text = buf.toString('utf8');

console.log('bytes:', buf.length, ' chars:', text.length);

// A byte-order mark would also mean a PowerShell round-trip touched this.
console.log('has BOM:', buf[0] === 0xef && buf[1] === 0xbb && buf[2] === 0xbf);

// U+FFFD is what a decoder emits for invalid bytes: its presence means data was
// already lost, not merely re-encoded.
const replacement = (text.match(/\uFFFD/g) || []).length;
console.log('U+FFFD replacement chars:', replacement);

// The two markers PowerShell's ANSI round-trip produces for € and £.
const mojibake = (text.match(/\u00c3[\u0080-\u00bf]/g) || []).length;
console.log('ANSI-mojibake sequences:', mojibake);

const checks = [
  ["'EUR': {'symbol': '\u20ac'", 'euro sign'],
  ["'GBP': {'symbol': '\u00a3'", 'pound sign'],
  ["'TZS': {'symbol': 'TSh'", 'shilling abbreviation'],
];
for (const [needle, label] of checks) {
  console.log(`${text.includes(needle) ? 'OK  ' : 'FAIL'} ${label}`);
}

const bad = replacement > 0 || mojibake > 0 || buf[0] === 0xef;
console.log(bad ? '\nENCODING BROKEN' : '\nEncoding intact.');
process.exit(bad ? 1 : 0);
