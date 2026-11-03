require('dotenv').config();
const {wrapEmailHtml} = require('./src/services/mailer');
const rawHtml = '<span class="badge">MALIPO YAMEFANIKIWA</span><h2>Malipo Yamekamilika!</h2><p>Malipo yako ya <strong>TZS 50,000</strong> yamefanikiwa. Escrow imehifadhiwa salama.</p><div class="info-box"><div class="info-row"><span class="info-label">Bidhaa</span><span class="info-value">Samsung Galaxy A14</span></div><div class="info-row"><span class="info-label">Seller</span><span class="info-value">John Doe</span></div><div class="info-row"><span class="info-label">Kiasi</span><span class="info-value">TZS 50,000</span></div><div class="info-row"><span class="info-label">Processing Fee</span><span class="info-value">TZS 920</span></div><div class="info-row"><span class="info-label">Jumla</span><span class="info-value">TZS 50,920</span></div></div><div class="security-box"><p class="security-title">Usalama</p><p class="security-text">Kamwe usimshirikie mtu mwingine maelezo ya malipo yako.</p></div><a href="https://www.sokovibe.co.tz" class="btn">Fungua Soko Vibe</a>';
const wrappedHtml = wrapEmailHtml(rawHtml);
const fetch = globalThis.fetch;
async function send(to) {
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + process.env.RESEND_API_KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({ from: 'Soko Vibe <no-reply@sokovibe.co.tz>', to: [to], subject: 'Test Clean Template - Soko Vibe', html: wrappedHtml, text: rawHtml.replace(/<[^>]+>/g, ' ') })
  });
  const data = await res.json();
  console.log(to, '->', res.status, JSON.stringify(data));
}
(async () => { await send('support@sokovibe.co.tz'); await send('atugavyenickson22@gmail.com'); })();
