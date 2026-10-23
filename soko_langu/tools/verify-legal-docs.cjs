// Verifies the generated legal pages actually resolve every key they reference.
//
// A blank section on a live legal page is worse than ugly wording: it reads as
// "this clause does not exist". This catches the two ways that happens - a shell
// asking for a section the generator did not emit, and a language block missing
// keys the other language has.
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const src = fs.readFileSync(path.join(root, 'hosting', 'legal_i18n.js'), 'utf8');

const keys = {};
const langRe = /^ {4}(\w+): \{([\s\S]*?)^ {4}\}/gm;
let m;
while ((m = langRe.exec(src))) {
  keys[m[1]] = [...m[2].matchAll(/'([a-z0-9_]+)':/g)].map((x) => x[1]);
}

console.log('languages:', Object.keys(keys).join(', '));
for (const l of Object.keys(keys)) console.log(`  ${l}: ${keys[l].length} keys`);

const sw = new Set(keys.sw || []);
const en = new Set(keys.en || []);
console.log('sw-only keys:', [...sw].filter((k) => !en.has(k)).join(', ') || 'none');
console.log('en-only keys:', [...en].filter((k) => !sw.has(k)).join(', ') || 'none');

const shells = [
  ['hosting/terms.html', 'tos'],
  ['hosting/privacy.html', 'pp'],
  ['server/landing/terms.html', 'tos'],
  ['server/landing/privacy.html', 'pp'],
];

let failures = 0;
for (const [file, prefix] of shells) {
  const html = fs.readFileSync(path.join(root, file), 'utf8');
  const used = [...html.matchAll(/data-i18n="([a-z0-9_]+)"/g)].map((x) => x[1]);
  const docKeys = used.filter((k) => k.startsWith(`${prefix}_`));
  const missing = docKeys.filter((k) => !sw.has(k) && !en.has(k));
  const sections = docKeys.filter((k) => new RegExp(`^${prefix}_section_\\d+_title$`).test(k)).length;
  console.log(
    `${file} | data-i18n: ${used.length} | doc keys: ${docKeys.length} | sections: ${sections} | MISSING: ${missing.join(',') || 'none'}`,
  );
  if (missing.length) failures++;
  if (!docKeys.includes(`${prefix}_intro`)) {
    console.log(`  !! ${file} does not render the intro paragraph`);
    failures++;
  }
}

// The shell for these documents is generated from the same section list, so a
// mismatch here means someone edited one by hand.
const expectSections = 10;
for (const [file, prefix] of shells) {
  const html = fs.readFileSync(path.join(root, file), 'utf8');
  const n = [...html.matchAll(new RegExp(`${prefix}_section_\\d+_title`, 'g'))].length;
  if (n !== expectSections) {
    console.log(`  !! ${file} renders ${n} sections, generator emits ${expectSections}`);
    failures++;
  }
}

console.log(failures ? `\nFAILED (${failures})` : '\nAll legal pages resolve cleanly.');
process.exit(failures ? 1 : 0);
