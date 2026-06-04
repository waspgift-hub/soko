/**
 * Retro-boost script: finds all completed boost transactions where the
 * product was never boosted (due to the old webhook ordering bug),
 * and applies the boost retroactively.
 *
 * Usage: node retroboost.js
 *   or   node retroboost.js <transactionId>
 *
 * Requires .env with FIREBASE_SERVICE_ACCOUNT_JSON.
 */
require('dotenv').config();
const admin = require('firebase-admin');

const BOOST_TIERS = {
  bronze: { price: 1500, days: 3 },
  silver: { price: 3000, days: 7 },
  gold: { price: 10000, days: 30 },
};

async function main() {
  if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
    const sa = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
    admin.initializeApp({ credential: admin.credential.cert(sa) });
  } else {
    console.error('FIREBASE_SERVICE_ACCOUNT_JSON not found in .env');
    process.exit(1);
  }

  const db = admin.firestore();
  const transactionId = process.argv[2];

  const force = process.argv.includes('--force');
  const validStatuses = force ? ['pending'] : ['completed'];

  let txDocs;
  if (transactionId) {
    const doc = await db.collection('transactions').doc(transactionId).get();
    if (!doc.exists) {
      console.log(`Transaction ${transactionId} not found.`);
      return;
    }
    txDocs = [doc];
  } else {
    const snap = await db.collection('transactions')
      .where('type', '==', 'boost')
      .where('status', '==', validStatuses[0])
      .get();
    txDocs = snap.docs;
  }

  console.log(`Found ${txDocs.length} completed boost transaction(s).`);

  let fixed = 0;
  let skipped = 0;
  let errors = 0;

  for (const doc of txDocs) {
    const tx = doc.data();
    const txId = doc.id;

    if (!tx.productId) {
      console.log(`  [SKIP]  ${txId}: no productId`);
      skipped++;
      continue;
    }

    try {
      const productDoc = await db.collection('products').doc(tx.productId).get();
      if (!productDoc.exists) {
        console.log(`  [SKIP]  ${txId}: product ${tx.productId} not found`);
        skipped++;
        continue;
      }

      const product = productDoc.data();
      if (product.isBoosted) {
        console.log(`  [SKIP]  ${txId}: product ${tx.productId} already boosted`);
        skipped++;
        continue;
      }

      const tier = tx.tier || 'bronze';
      const tierConfig = BOOST_TIERS[tier] || BOOST_TIERS.bronze;
      const now = new Date();
      const boostedUntil = new Date(now.getTime() + tierConfig.days * 24 * 60 * 60 * 1000);

      await db.collection('products').doc(tx.productId).update({
        isBoosted: true,
        boostedUntil: admin.firestore.Timestamp.fromDate(boostedUntil),
        boostTier: tier,
        isFeatured: true,
        featuredUntil: admin.firestore.Timestamp.fromDate(boostedUntil),
      });

      console.log(`  [FIX]   ${txId}: boosted product ${tx.productId} (${tier}, ${tierConfig.days} days)`);
      fixed++;
    } catch (e) {
      console.error(`  [ERROR] ${txId}: ${e.message}`);
      errors++;
    }
  }

  console.log(`\nDone: ${fixed} fixed, ${skipped} skipped, ${errors} errors`);
}

main().catch(console.error);
