// Firestore rules are exercised against the real emulator, not a mock: a
// rule's behaviour is the product of the rules language, the project config and
// the request shape, so only the emulator can prove an update is denied.
//
// Run with: firebase emulators:exec --only firestore "npm run test:rules"
// (from the Flutter project root, where firebase.json lives). Without the
// emulator the suite is skipped rather than failed, so `npm test` stays usable
// on a machine with no Java/Firebase tooling.
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const fs = require('fs');
const path = require('path');
const { test } = require('node:test');

const RULES_PATH = path.resolve(__dirname, '..', '..', 'firestore.rules');
const HAS_EMULATOR = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
const skip = HAS_EMULATOR ? false : 'FIRESTORE_EMULATOR_HOST is not set';

let env;
test.before(async () => {
  if (!HAS_EMULATOR) return;
  env = await initializeTestEnvironment({
    projectId: 'soko-test',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8') },
  });
});
test.after(async () => {
  if (env) await env.cleanup();
});

test('unauthenticated cannot read users', { skip }, async () => {
  const ctx = env.unauthenticatedContext();
  const db = ctx.firestore();
  await assertFails(db.collection('users').doc('u1').get());
});

test('owner can read own user', { skip }, async () => {
  await env.withSecurityRulesDisabled(async (c) => {
    await c.firestore().collection('users').doc('u1').set({ displayName: 'A' });
  });
  const ctx = env.authenticatedContext('u1');
  const db = ctx.firestore();
  await assertSucceeds(db.collection('users').doc('u1').get());
});

test('non-owner cannot read other user', { skip }, async () => {
  const ctx = env.authenticatedContext('u2');
  const db = ctx.firestore();
  await assertFails(db.collection('users').doc('u1').get());
});

test('only the owner may flip their own visibility', { skip }, async () => {
  await env.withSecurityRulesDisabled(async (c) => {
    await c.firestore().collection('users').doc('u1').set({
      visibility: {
        isPrivate: false,
        showFollowers: true,
        showFollowing: true,
        showProducts: true,
        allowContactDiscovery: true,
      },
    });
  });
  const owner = env.authenticatedContext('u1').firestore();
  const stranger = env.authenticatedContext('u2').firestore();
  const nextVisibility = {
    isPrivate: true,
    showFollowers: true,
    showFollowing: true,
    showProducts: true,
    allowContactDiscovery: true,
  };

  await assertFails(stranger.collection('users').doc('u1').update({ visibility: nextVisibility }));
  await assertSucceeds(owner.collection('users').doc('u1').update({ visibility: nextVisibility }));
});

test('follower counts are server-owned', { skip }, async () => {
  await env.withSecurityRulesDisabled(async (c) => {
    await c.firestore().collection('userPublic').doc('u1').set({ followerCount: 3 });
  });
  const db = env.authenticatedContext('u1').firestore();
  await assertFails(db.collection('userPublic').doc('u1').update({ followerCount: 99 }));
});

// A verified-purchase badge is only meaningful if the server proved the order,
// so a client that asserts it is either forged or misreading its own data. Both
// cases must be denied, while an ordinary review must still land.
test('a client cannot self-declare a verified purchase', { skip }, async () => {
  await env.withSecurityRulesDisabled(async (c) => {
    await c.firestore().collection('products').doc('p1').set({ sellerId: 'seller-1' });
  });
  const db = env.authenticatedContext('buyer-1').firestore();
  await assertFails(
    db.collection('reviews').add({
      productId: 'p1',
      sellerId: 'seller-1',
      userId: 'buyer-1',
      rating: 5,
      comment: 'Nzuri sana',
      isVerifiedPurchase: true,
    }),
  );
});

test('an unverified review is still accepted', { skip }, async () => {
  await env.withSecurityRulesDisabled(async (c) => {
    await c.firestore().collection('products').doc('p2').set({ sellerId: 'seller-2' });
  });
  const db = env.authenticatedContext('buyer-2').firestore();
  const base = {
    productId: 'p2',
    sellerId: 'seller-2',
    userId: 'buyer-2',
    rating: 4,
    comment: 'Sawa',
  };
  await assertSucceeds(db.collection('reviews').add(base));
  await assertSucceeds(
    db.collection('reviews').add({ ...base, isVerifiedPurchase: false }),
  );
});
