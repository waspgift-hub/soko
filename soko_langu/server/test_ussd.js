require('dotenv').config();
const { clickpesaCollect, clickpesaPaymentStatus } = require('./clickpesa');

async function main() {
  const phone = '255719537300';
  const amount = 1000;
  const orderRef = 't' + Date.now().toString(36) + Math.random().toString(36).substring(2,6);

  console.log(`Sending USSD push to ${phone}, TZS ${amount}, ref: ${orderRef}`);

  try {
    const result = await clickpesaCollect({
      amount,
      orderReference: orderRef,
      phoneNumber: phone,
    });
    console.log('SUCCESS:', JSON.stringify(result, null, 2));

    console.log('\nPolling status every 10s...');
    for (let i = 0; i < 12; i++) {
      await new Promise(r => setTimeout(r, 10000));
      try {
        const status = await clickpesaPaymentStatus(orderRef);
        const s = JSON.stringify(status).toLowerCase();
        console.log(`Poll ${i+1}:`, JSON.stringify(status).substring(0, 300));
        if (s.includes('completed') || s.includes('success') || s.includes('payment_received')) {
          console.log('\n✅ COMPLETED!');
          process.exit(0);
        }
        if (s.includes('failed') || s.includes('cancelled') || s.includes('expired')) {
          console.log('\n❌ FAILED!');
          process.exit(1);
        }
      } catch (e) {
        console.log(`Poll ${i+1}: ${e.message}`);
      }
    }
    console.log('\n⏰ Timeout');
  } catch (e) {
    console.log('FAILED:', e.message);
    if (e.response?.data) console.log('Response:', JSON.stringify(e.response.data));
  }
}

main();
