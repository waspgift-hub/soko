#!/usr/bin/env node
/**
 * One-off backfill: project every existing `users/{uid}` into `userPublic/{uid}`.
 *
 * Run this ONCE after deploying the firestore.rules change that scopes
 * `users` reads to owner-or-admin. Without it, existing users have no
 * `userPublic` document and their display name / KYC badge / presence will be
 * missing from chat lists and seller cards until they next edit their profile.
 *
 * Safe to re-run: the write is `set(..., { merge: true })` and the projection is
 * derived, so a second pass is a no-op in content terms.
 *
 * Usage (from server/):
 *   FIREBASE_PROJECT=your-project node scripts/backfill-user-public.js
 *   FIREBASE_PROJECT=your-project node scripts/backfill-user-public.js --limit 1000
 *
 * Requires the Admin SDK credentials already used by the API (GOOGLE_APPLICATION
 * _CREDENTIALS, or FIREBASE_PROJECT + the default credential chain). This is an
 * Admin-SDK write; no client rule grants it, which is the point.
 */
const { backfillUserPublic } = require('../src/services/account-store');

async function main() {
  const limitArg = process.argv.indexOf('--limit');
  const limit = limitArg > -1 ? Number(process.argv[limitArg + 1]) : undefined;

  if (!process.env.FIREBASE_PROJECT && !process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    console.error(
      'Set FIREBASE_PROJECT (and Application Default Credentials) before running this.',
    );
    process.exit(1);
  }

  const started = Date.now();
  const { scanned, created } = await backfillUserPublic({ limit });
  console.log(
    `backfilled ${created}/${scanned} users into userPublic in ${(
      (Date.now() - started) /
      1000
    ).toFixed(1)}s`,
  );
}

main().catch((e) => {
  console.error('backfill failed:', e.message);
  process.exit(1);
});