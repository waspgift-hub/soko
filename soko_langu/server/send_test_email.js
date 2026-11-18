require('dotenv').config();
const { sendMail } = require('./src/services/mailer');
const html = '<h2>Test to support@ - Soko Vibe</h2><p>Testing delivery to support address.</p>';
(async () => {
  try {
    const r = await sendMail('any', 'Test to support - Soko Vibe', html, 'support@sokovibe.co.tz');
    console.log('support@sokovibe.co.tz ->', r);
  } catch (e) {
    console.error('ERROR:', e && e.message ? e.message : e);
  } finally {
    process.exit(0);
  }
})();