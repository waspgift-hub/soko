require('dotenv').config();
const {sendMail} = require('./src/services/mailer');
const html = '<h2>Malipo Yamefanikiwa!</h2><p>Malipo yako ya TZS 50,000 yamefanikiwa. Escrow imehifadhiwa.</p><p><strong>Bidhaa:</strong> Samsung Galaxy A14</p><p><strong>Seller:</strong> John Doe</p><a href="https://www.sokovibe.co.tz" class="button">Fungua Soko Vibe</a>';
sendMail('gift@sokovibe.co.tz','Test Glass Liquid Template', html).then(r => console.log('Result:', r)).catch(e => console.error('Error:', e.message));
