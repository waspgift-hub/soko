// One-shot migration: normalize legacy payment-method spellings in Firestore
// orders/transactions collections to canonical 'escrow' | 'cod'.
// Usage: node scripts/normalize-payment-methods.js [--commit]
// Default is dry-run.
const admin = require('firebase-admin');
require('dotenv').config();

const ALIASES = { escrow: 'escrow', mobile_money: 'escrow', cod: 'cod', cash: 'cod' };

async function main() {
  const commit = process.argv.includes('--commit');
  if (!admin.apps.length) admin.initializeApp();
  const db = admin.firestore();
  const collections = ['orders', 'transactions'];
  let scanned = 0, updated = 0, ambiguous = 0;
  for (const col of collections) {
    const snap = await db.collection(col).get();
    for (const d of snap.docs) {
      scanned++;
      const data = d.data() || {};
      const raw = data.paymentMethod || data.preferredPaymentMethod;
      if (!raw) { ambiguous++; continue; }
      const key = String(raw).trim().toLowerCase();
      const canonical = ALIASES[key];
      if (!canonical) { ambiguous++; console.log('AMBIGUOUS', col, d.id, raw); continue; }
      if (raw !== canonical) {
        console.log('NORMALIZE', col, d.id, raw, '->', canonical);
        if (commit) {
          await d.ref.set({ paymentMethod: canonical, paymentStatus: canonical === 'cod' ? (data.paymentStatus || 'cash_due') : (data.paymentStatus || 'unpaid'), updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
          updated++;
        }
      }
    }
  }
  console.log(JSON.stringify({ scanned, updated, ambiguous, commit }, null, 2));
}

main().catch((e) => { console.error(e); process.exit(1); });