#!/usr/bin/env node
// verify-zero-state.js — read-only Firestore zero-state check.
//
// Fails (exit 1) if any BUSINESS collection in the target project has
// documents. The user's decision (2026-09-24): users, notifications and
// landing_waitlist are tolerated as pre-existing leftovers, so their counts
// are only reported, never failed on.
//
// Business collections come from the MODELS map in firestore-store.js — keep
// this list in sync if that map grows.
//
// Usage:
//   node scripts/verify-zero-state.js            # uses server/.env creds
//   FIREBASE_SERVICE_ACCOUNT_JSON=... node ...
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

const { Firestore } = require('firebase-admin/firestore');
const { initializeApp, cert } = require('firebase-admin/app');

const BUSINESS_COLLECTIONS = [
  'sellerProfiles', 'products', 'productMedia', 'categories', 'orders',
  'orderItems', 'shippingQuotes', 'payments', 'paymentAttempts',
  'escrowHolds', 'escrowTransactions', 'commissionTransactions', 'refunds',
  'payoutTransactions', 'receipts', 'wallets', 'walletTransactions',
  'withdrawals', 'otpCredentials', 'disputes', 'disputeEvidence',
  'auditLogs', 'webhookEvents', 'addresses', 'userSettings', 'devices',
  'referrals', 'boosts', 'kycApplications', 'moderationReports',
  'adminSettings', 'reconciliations', 'sponsoredCampaigns',
  'campaignPlacements', 'campaignEvents', 'campaignImpressions',
  'campaignClicks', 'campaignAttributions', 'campaignPayments',
  'campaignAuditLogs',
];

// Pre-existing leftovers in the target project — report only, never fail.
const TOLERATED = ['users', 'notifications', 'landing_waitlist'];

async function main() {
  const saJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (!saJson) {
    console.error('verify-zero-state: FIREBASE_SERVICE_ACCOUNT_JSON not set; can derive project from server/.env');
    process.exit(2);
  }
  const sa = JSON.parse(saJson);
  const app = initializeApp({ credential: cert(sa), projectId: sa.project_id });
  const db = new Firestore({ credentials: sa, projectId: sa.project_id });

  let failures = [];
  let tolerances = [];

  for (const [i, col] of [...BUSINESS_COLLECTIONS, ...TOLERATED].entries()) {
    const count = (await db.collection(col).count().get()).data().count;
    if (BUSINESS_COLLECTIONS.includes(col)) {
      const marker = count > 0 ? '✗' : '✓';
      if (count > 0) failures.push(`${col}=${count}`);
      console.log(`  ${marker} ${col.padEnd(26)} ${String(count).padStart(4)}`);
    } else {
      tolerances.push(`${col}=${count}`);
      console.log(`  ~  ${col.padEnd(26)} ${String(count).padStart(4)}  (tolerated)`);
    }
    await new Promise(r => setTimeout(r, 120)); // stay under per-project read QPS
  }

  console.log('');
  if (failures.length) {
    console.log(`NOT ZERO: ${failures.join(', ')}`);
    process.exit(1);
  }
  console.log('ZERO-STATE OK: all business collections empty.');
  if (tolerances.length) console.log(`Tolerated (pre-existing): ${tolerances.join(', ')}`);
}

main().catch(err => {
  console.error('verify-zero-state failed:', err.message);
  process.exit(1);
});