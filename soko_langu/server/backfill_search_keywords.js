require('dotenv').config();
const admin = require('firebase-admin');

if (!process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
  console.error('FIREBASE_SERVICE_ACCOUNT_JSON env var is required');
  process.exit(1);
}

const sa = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

function generateSearchKeywords(name, description, category, brand) {
  const words = new Set();
  const text = `${name} ${description} ${category} ${brand || ''}`;
  for (const part of text.split(/[\s,.\-]+/)) {
    const w = part.trim().toLowerCase();
    if (w.length >= 2) words.add(w);
  }
  return Array.from(words);
}

async function backfill() {
  const snapshot = await db.collection('products')
    .where('isActive', '==', true)
    .get();

  console.log(`Found ${snapshot.docs.length} active products`);

  let updated = 0;
  let skipped = 0;

  for (const doc of snapshot.docs) {
    const data = doc.data();
    const existing = data.searchKeywords;

    if (existing && Array.isArray(existing) && existing.length > 0) {
      skipped++;
      continue;
    }

    const keywords = generateSearchKeywords(
      data.name || '',
      data.description || '',
      data.category || '',
      data.brand || null,
    );

    await doc.ref.update({ searchKeywords: keywords });
    updated++;
    console.log(`[${updated}] ${doc.id}: ${data.name} -> ${keywords.length} keywords`);
  }

  console.log(`\nDone. Updated: ${updated}, Skipped (already have keywords): ${skipped}`);
  process.exit(0);
}

backfill().catch((err) => {
  console.error('Backfill failed:', err);
  process.exit(1);
});
