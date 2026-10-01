const { getFirebaseFirestore } = require('../config/firebase');

// Mobile-money payouts need a phone number, and the two stores do not agree on
// identity: Postgres/Firestore-mirrored commerce rows are keyed by a UUID, while
// the `users` Firestore collection is keyed by the Firebase Auth UID. Looking a
// user up in Firestore with the UUID silently finds nothing, so a seller who
// signed in with Google (phone NULL in the database, phone present in
// Firestore) had no number to pay out to.
//
// The order of the fallbacks below is deliberate:
//   1. the number captured when the request was made — it is the one the user
//      confirmed, and it survives later profile edits
//   2. the phone on the database user row
//   3. the phone on the Firestore user document, looked up by firebaseUid and
//      only then by the raw id (for callers that legitimately hold a UID)

/**
 * Resolves a payout phone number for a user.
 *
 * @param {object} opts
 * @param {string} [opts.capturedPhone] phone recorded at request time
 * @param {string} [opts.dbPhone] phone from the database user row
 * @param {string} [opts.firebaseUid] Firebase Auth UID of the user
 * @param {string} [opts.userId] database id, used only as a last-resort doc id
 * @param {object} [opts.db] Firestore handle override, for tests
 * @returns {Promise<string|null>}
 */
async function resolvePayoutPhone({ capturedPhone, dbPhone, firebaseUid, userId, db: dbOverride } = {}) {
  if (capturedPhone) return capturedPhone;
  if (dbPhone) return dbPhone;

  let db = dbOverride;
  if (!db) {
    try {
      db = getFirebaseFirestore();
    } catch (_) {
      return null;
    }
  }
  if (!db) return null;

  // The Firebase UID is the Firestore document key, so it must be tried first.
  // Using the database UUID here returns a non-existent doc and the payout is
  // refused with a misleading "no phone on file".
  const candidateIds = [firebaseUid, userId].filter((v) => v !== undefined && v !== null && v !== '');
  for (const id of candidateIds) {
    try {
      const snap = await db.collection('users').doc(String(id)).get();
      if (!snap || !snap.exists) continue;
      const data = snap.data() || {};
      const phone = data.phone || data.phoneNumber || data.msisdn || null;
      if (phone) return phone;
    } catch (err) {
      // One unreadable document must not abort the remaining candidates.
      console.error(`[payout-phone] Firestore lookup failed for ${id}: ${err.message}`);
    }
  }
  return null;
}

module.exports = { resolvePayoutPhone };
