const fs = require('fs');
const h = fs.readFileSync('lib/services/localization_service.dart', 'utf8');
const lines = h.split('\n');
const sw = lines.findIndex((l) => l.includes('enter_pin_unlock') && l.includes('Weka'));
const en = lines.findIndex((l) => l.includes('enter_pin_unlock') && l.includes('Enter your PIN'));
console.log('sw index:', sw, 'line:', sw + 1);
console.log('en index:', en, 'line:', en + 1);
console.log('sw line:', JSON.stringify(lines[sw]));
console.log('en line:', JSON.stringify(lines[en]));
console.log('sw indent:', JSON.stringify(lines[sw].match(/^(\s*)/)[1]));
console.log('en indent:', JSON.stringify(lines[en].match(/^(\s*)/)[1]));
// Show the 3 lines before each anchor (to confirm the block shape)
console.log('\nsw context (3 lines before):');
lines.slice(sw - 3, sw).forEach((l, i) => console.log(`  ${sw - 3 + i + 1}: ${JSON.stringify(l)}`));
console.log('en context (3 lines before):');
lines.slice(en - 3, en).forEach((l, i) => console.log(`  ${en - 3 + i + 1}: ${JSON.stringify(l)}`));
