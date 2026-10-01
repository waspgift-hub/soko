/**
 * Fraud and escrow-policy checks shared by the legacy order routes.
 *
 * Why this module exists: orders-compat.js called `checkSuspended()` and read
 * `ESCROW_REGIONAL_DAYS` / `ESCROW_LOCAL_DAYS` without ever defining or
 * importing them. Both were only present in the old monolith `server/index.js`,
 * which is not loaded by the current entrypoint, so every marketplace checkout
 * through that router died with `checkSuspended is not defined` — thrown before
 * any payment was created, so no money was ever at risk. Moving the real
 * definitions here is what makes the route importable at all.
 */

const { getFirebaseFirestore } = require('../../config/firebase');

// Escrow auto-release windows. These are business policy, not tunables: a
// regional shipment is handed to a courier who may sit on it for days, while a
// local one is expected to be inspected the same day. The legacy monolith used
// the same values, so keeping them preserves existing order behaviour.
const ESCROW_REGIONAL_DAYS = 7;
const ESCROW_LOCAL_DAYS = 3;

/**
 * A suspended buyer must not be able to start a payment.
 *
 * The flag is read from Firestore (`users/{uid}`) because suspension is an
 * admin action and admins operate on Firestore documents. Firestore is treated
 * as best-effort here: if it is unreachable, a missing admin tool must not take
 * checkout offline for every buyer, so the check fails open. The caller's own
 * payment limits and duplicate detection still apply.
 *
 * @returns {Promise<boolean>} true when the account is suspended
 */
async function checkSuspended(uid) {
  if (!uid) return false;
  let db;
  try {
    db = getFirebaseFirestore();
  } catch (_) {
    return false;
  }
  if (!db) return false;
  try {
    const doc = await db.collection('users').doc(uid).get();
    if (!doc.exists) return false;
    const data = doc.data() || {};
    return data.suspended === true || data.isSuspended === true || data.accountStatus === 'suspended';
  } catch (err) {
    console.error('[fraud] suspension check failed, allowing checkout:', err.message);
    return false;
  }
}

module.exports = { checkSuspended, ESCROW_REGIONAL_DAYS, ESCROW_LOCAL_DAYS };
