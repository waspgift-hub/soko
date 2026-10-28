const fs = require('fs');
const t = fs.readFileSync(process.env.TEMP + '/opencode/staged_blob.dart', 'utf8');
console.log('staged blob bytes:', t.length, 'chars (approx):', t.length);
console.log('U+FFFD replacement chars:', (t.match(/\uFFFD/g) || []).length);
console.log('ANSI-mojibake sequences:', (t.match(/\u00c3[\u0080-\u00bf]/g) || []).length);
const i = t.indexOf("'EUR'");
console.log('EUR line:', JSON.stringify(t.slice(i, i + 46)));
console.log('unlock_biometric present:', t.includes("'unlock_biometric': 'Fungua kwa alama ya vidole'"));
console.log('upload_failed_many present (theirs, should be ABSENT in my commit):', t.includes("'upload_failed_many': 'Picha {n} hazikupakiwa.'"));
