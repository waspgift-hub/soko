const fs = require('fs');
const content = fs.readFileSync('src/services/mailer.js', 'utf8');
const start = content.indexOf('function wrapEmailHtml');
const end = content.indexOf('async function sendMail');
const template = fs.readFileSync('glass_template3.txt', 'utf8');
const newFunc = template.replace('PLACEHOLDER_HTML', '` + html + `');
const result = content.substring(0, start) + newFunc + content.substring(end);
fs.writeFileSync('src/services/mailer.js', result);
console.log('Done');
