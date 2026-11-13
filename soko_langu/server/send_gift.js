require('dotenv').config();
const {sendMail} = require('./src/services/mailer');
const html = '<span class="badge">MALIPO YAMEFANIKIWA</span><h2>Malipo Yamekamilika!</h2><p>Malipo yako ya <strong>TZS 50,000</strong> yamefanikiwa. Escrow imehifadhiwa salama.</p><div class="info-box"><div class="info-row"><span class="info-label">Bidhaa</span><span class="info-value">Samsung Galaxy A14</span></div><div class="info-row"><span class="info-label">Seller</span><span class="info-value">John Doe</span></div><div class="info-row"><span class="info-label">Kiasi</span><span class="info-value">TZS 50,000</span></div><div class="info-row"><span class="info-label">Processing Fee</span><span class="info-value">TZS 920</span></div><div class="info-row"><span class="info-label">Jumla</span><span class="info-value">TZS 50,920</span></div></div><div class="security-box"><p class="security-title">Usalama</p><p class="security-text">Kamwe usimshirikie mtu mwingine maelezo ya malipo yako.</p></div><a href="https://www.sokovibe.co.tz" class="btn">Fungua Soko Vibe</a>';
(async () => {
  const r = await sendMail('any', 'Test Clean Template - Soko Vibe', html, 'gift@sokovibe.co.tz');
  console.log('gift@sokovibe.co.tz ->', r);
})();
