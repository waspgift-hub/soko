const fs = require('fs');
const content = fs.readFileSync('src/services/mailer.js', 'utf8');
const modified = content.replace('async function sendMail(to, subject, html) {', 'async function sendMail(to, subject, html, recipientOverride) {');
const modified2 = modified.replace("  const recipient = 'gift@sokovibe.co.tz';", "  const recipient = recipientOverride || 'gift@sokovibe.co.tz';");
fs.writeFileSync('src/services/mailer.js', modified2);
console.log('Done');
