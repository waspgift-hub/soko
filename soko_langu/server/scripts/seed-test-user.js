#!/usr/bin/env node
// seed-test-user.js — creates ONE e2e test account able to operate every
// mission in the app (buyer + seller + KYC-verified) without skipping.
//
// Idempotent: re-running updates the existing account instead of duplicating
// it, and never touches business collections. Requires server/.env creds.
//
// Usage:
//   node scripts/seed-test-user.js            # loads server/.env
//   FIREBASE_SERVICE_ACCOUNT_JSON=... node scripts/seed-test-user.js
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

const { initializeApp, cert } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

const TEST_EMAIL = process.env.TEST_USER_EMAIL || 'langusoko@gmail.com';
const TEST_PASSWORD = process.env.TEST_USER_PASSWORD || 'Test@1234';
const TEST_PHONE = process.env.TEST_USER_PHONE || '+255719537300';
const TEST_NAME = process.env.TEST_USER_NAME || 'Mwanzo Test';

// Accounts created under the previous default are migrated to the new email
// so the repository keeps exactly ONE test user.
const LEGACY_EMAIL = 'test@sokovibe.co.tz';

async function main() {
  const saJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (!saJson) {
    console.error('seed-test-user: FIREBASE_SERVICE_ACCOUNT_JSON not set (found in server/.env)');
    process.exit(2);
  }
  const sa = JSON.parse(saJson);
  const app = initializeApp({ credential: cert(sa), projectId: sa.project_id }, 'seed-test-user');
  const auth = getAuth(app);
  const db = getFirestore(app);

  let uid;
  let created = false;
  let migrated = false;
  try {
    const existing = await auth.getUserByEmail(TEST_EMAIL);
    uid = existing.uid;
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
    let record;
    try {
      const legacy = await auth.getUserByEmail(LEGACY_EMAIL);
      record = await auth.updateUser(legacy.uid, {
        email: TEST_EMAIL,
        phoneNumber: TEST_PHONE,
        displayName: TEST_NAME,
      });
      migrated = true;
    } catch (e2) {
      if (e2.code === 'auth/user-not-found') {
        record = await auth.createUser({
          email: TEST_EMAIL,
          phoneNumber: TEST_PHONE,
          password: TEST_PASSWORD,
          emailVerified: true,
          displayName: TEST_NAME,
        });
        created = true;
      } else {
        throw e2;
      }
    }
    uid = record.uid;
  }

  await db.collection('users').doc(uid).set({
    displayName: TEST_NAME,
    email: TEST_EMAIL,
    phone: TEST_PHONE,
    username: 'mwanzo_test',
    bio: 'Tester anayeendesha misheni zote za app',
    location: 'Dar es Salaam',
    mood: '',
    profileImage: '',
    paymentNumbers: {},
    shopBanner: '',
    shopBannerColor: '#00C853',
    shopAccentColor: '#009624',
    latitude: -6.7924,
    longitude: 39.2083,
    gender: 'Male',
    dateOfBirth: '1995-01-01',
    coins: 0,
    viewerCoins: 0,
    sellerBalance: 0,
    soldCount: 0,
    isAdmin: false,
    isSuspended: false,
    // KYC stand: approved so the account can sell with the trust badge and
    // the seller missions (create ad, flash sale, boost) are unlocked.
    kyc: {
      approved: true,
      status: 'approved',
      submittedAt: FieldValue.serverTimestamp(),
      approvedAt: FieldValue.serverTimestamp(),
    },
    emailVerified: true,
    phoneVerified: true,
    updatedAt: FieldValue.serverTimestamp(),
    createdAt: FieldValue.serverTimestamp(),
  }, { merge: true });

  console.log('');
  console.log(migrated
    ? `TEST USER MIGRATED from ${LEGACY_EMAIL} to ${TEST_EMAIL} (uid=${uid})`
    : created
      ? `TEST USER CREATED (uid=${uid})`
      : `TEST USER ALREADY EXISTS — fields refreshed (uid=${uid})`);
  console.log('──────────────────────────────────────────────');
  console.log(`  Login email : ${TEST_EMAIL}`);
  console.log(`  Password    : ${TEST_PASSWORD}`);
  console.log(`  Phone       : ${TEST_PHONE}`);
  console.log(`  Name        : ${TEST_NAME}`);
  console.log('');
  console.log('Log in with these credentials in the app, then run every mission');
  console.log('without skipping: profile edit, KYC passes, add product, flash');
  console.log('sale, boost, chat, wishlist, orders/checkout, notifications.');
}

main().catch((err) => {
  console.error('seed-test-user failed:', err.message);
  process.exit(1);
});