#!/usr/bin/env node
// purge-sponsored-data.js — delete the Firestore collections that backed the
// removed Sponsored Ads module (K2: delete existing campaigns).
//
// The sponsored module was fully deleted from the codebase; this script is the
// one-time data cleanup so the old campaign/placement rows are gone from
// production. Run it once, then verify with verify-zero-state.js semantics or
// a re-run (collections should report 0).
//
// Usage:
//   node scripts/purge-sponsored-data.js            # applies deletion
//   node scripts/purge-sponsored-data.js --dry-run  # only report counts
//
// Credentials come from FIREBASE_SERVICE_ACCOUNT_JSON (server/.env via dotenv)
// exactly like verify-zero-state.js uses.
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

const { Firestore } = require('firebase-admin/firestore');
const { initializeApp, cert } = require('firebase-admin/app');

const SPONSORED_COLLECTIONS = [
  'sponsoredCampaigns',
  'campaignPlacements',
  'campaignEvents',
  'campaignImpressions',
  'campaignClicks',
  'campaignAttributions',
  'campaignPayments',
  'campaignAuditLogs',
];

const DRY_RUN = process.argv.includes('--dry-run');
const BATCH_SIZE = 300; // single Firestore batch / one get-then-delete pass

async function main() {
  const saJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (!saJson) {
    console.error('purge: FIREBASE_SERVICE_ACCOUNT_JSON not set (can derive from server/.env)');
    process.exit(2);
  }
  const sa = JSON.parse(saJson);
  const app = initializeApp({ credential: cert(sa), projectId: sa.project_id });
  const db = new Firestore({ credentials: sa, projectId: sa.project_id });

  console.log(`project: ${sa.project_id}  mode: ${DRY_RUN ? 'DRY-RUN (no writes)' : 'DELETE'}`);

  let deletedTotal = 0;
  for (const col of SPONSORED_COLLECTIONS) {
    let deleted = 0;
    while (true) {
      const snap = await db.collection(col).limit(BATCH_SIZE).get();
      if (snap.size === 0) break;
      if (!DRY_RUN) {
        const batch = db.batch();
        snap.docs.forEach((doc) => batch.delete(doc.ref));
        await batch.commit();
      }
      deleted += snap.size;
      deletedTotal += snap.size;
      // Stay under per-project write/read QPS; purge is a rare one-off.
      await new Promise((r) => setTimeout(r, 200));
    }
    console.log(`  ${DRY_RUN ? '~' : 'x'} ${col.padEnd(22)} ${String(deleted).padStart(5)} deleted`);
  }

  console.log(`\n${DRY_RUN ? 'DRY-RUN total' : 'Total deleted'}: ${deletedTotal} docs across ${SPONSORED_COLLECTIONS.length} collections`);
}

main().catch((err) => {
  console.error('purge-sponsored-data failed:', err.message);
  process.exit(1);
});