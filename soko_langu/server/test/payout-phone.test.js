// Regression tests for payout phone resolution.
//
// The Firestore `users` collection is keyed by Firebase Auth UID, while the
// commerce tables are keyed by a database UUID. The old lookup used the UUID as
// the Firestore document id, so it found nothing and every seller without a
// database phone was refused a payout — and the existing test could not catch it
// because its fake `doc()` ignored the id it was given. These tests assert on
// the id that is actually used.

const { test } = require('node:test');
const assert = require('node:assert/strict');

const { resolvePayoutPhone } = require('../src/services/payout-phone');

// Records every document id the lookup asks for.
function trackingDb(usersById) {
  const asked = [];
  return {
    asked,
    collection: (name) => ({
      doc: (id) => {
        asked.push(id);
        return {
          get: async () => {
            const data = usersById[String(id)];
            return data ? { exists: true, data: () => data } : { exists: false, data: () => undefined };
          },
        };
      },
    }),
  };
}

const UID = 'firebase-uid-abc';
const UUID = '3f8b1c22-9d4e-4a7b-8c11-6e2f0a9b5d31';

test('the captured phone wins over every other source', async () => {
  const db = trackingDb({});
  const got = await resolvePayoutPhone({
    capturedPhone: '255700111222', dbPhone: '255700333444', firebaseUid: UID, userId: UUID, db,
  });
  assert.equal(got, '255700111222');
  assert.equal(db.asked.length, 0, 'no lookup needed when the phone is already known');
});

test('the database phone is used without touching Firestore', async () => {
  const db = trackingDb({});
  const got = await resolvePayoutPhone({ dbPhone: '255700333444', firebaseUid: UID, userId: UUID, db });
  assert.equal(got, '255700333444');
  assert.equal(db.asked.length, 0);
});

test('Firestore is looked up by the Firebase UID, not the database UUID', async () => {
  // Only the UID-keyed document exists — the real-world shape for a Google
  // sign-in user. Using the UUID would return exists:false and refuse the payout.
  const db = trackingDb({ [UID]: { phone: '+255733333333' } });
  const got = await resolvePayoutPhone({ firebaseUid: UID, userId: UUID, db });
  assert.equal(got, '+255733333333');
  assert.deepEqual(db.asked, [UID], 'the Firebase UID must be the first document tried');
});

test('the database id is only used when there is no Firebase UID', async () => {
  const db = trackingDb({ [UUID]: { phone: '255755555555' } });
  const got = await resolvePayoutPhone({ userId: UUID, db });
  assert.equal(got, '255755555555');
  assert.deepEqual(db.asked, [UUID]);
});

test('both ids are tried when the UID document has no phone', async () => {
  const db = trackingDb({ [UID]: { displayName: 'No phone here' }, [UUID]: { phone: '255766666666' } });
  const got = await resolvePayoutPhone({ firebaseUid: UID, userId: UUID, db });
  assert.equal(got, '255766666666');
  assert.deepEqual(db.asked, [UID, UUID]);
});

test('the phoneNumber and msisdn field names are both accepted', async () => {
  const db1 = trackingDb({ [UID]: { phoneNumber: '255711111111' } });
  assert.equal(await resolvePayoutPhone({ firebaseUid: UID, db: db1 }), '255711111111');
  const db2 = trackingDb({ [UID]: { msisdn: '255722222222' } });
  assert.equal(await resolvePayoutPhone({ firebaseUid: UID, db: db2 }), '255722222222');
});

test('no phone anywhere resolves to null', async () => {
  const db = trackingDb({ [UID]: { displayName: 'x' } });
  assert.equal(await resolvePayoutPhone({ firebaseUid: UID, userId: UUID, db }), null);
});

test('an unreadable Firestore document does not abort the remaining candidates', async () => {
  const db = {
    collection: () => ({
      doc: (id) => ({
        get: async () => {
          if (String(id) === UID) throw new Error('permission denied');
          return { exists: true, data: () => ({ phone: '255777777777' }) };
        },
      }),
    }),
  };
  assert.equal(await resolvePayoutPhone({ firebaseUid: UID, userId: UUID, db }), '255777777777');
});

test('a missing Firestore handle resolves to null instead of throwing', async () => {
  assert.equal(await resolvePayoutPhone({ firebaseUid: UID, userId: UUID, db: null }), null);
});
