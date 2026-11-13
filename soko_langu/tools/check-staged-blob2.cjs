const fs = require('fs');
const t = fs.readFileSync(process.env.TEMP + '/opencode/staged_blob2.dart', 'utf8');
console.log('staged blob bytes:', t.length);
console.log('U+FFFD:', (t.match(/\uFFFD/g) || []).length);
console.log('mojibake:', (t.match(/\u00c3[\u0080-\u00bf]/g) || []).length);
console.log('unlock_biometric:', t.includes("'unlock_biometric': 'Fungua kwa alama ya vidole'"));
console.log('upload_failed (theirs, should be ABSENT):', t.includes("'upload_failed_many': 'Picha {n} hazikupakiwa.'"));
console.log('euro sign intact:', t.includes("'EUR': {'symbol': '\u20ac'"));
