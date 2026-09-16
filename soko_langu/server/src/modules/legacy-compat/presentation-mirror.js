// Phase B/C compat presentation mirror: keeps the legacy Firestore `orders` +
// `transactions` docs in sync with the authoritative Postgres order status so
// the existing Flutter buyer/seller screens (which stream those collections)
// reflect v2-driven transitions — e.g. after `/api/v1/payments/webhook` moves
// an order to IN_ESCROW the app stops being stuck on "pending".
//
// Purely best-effort read-only presentation: a Firestore failure must never
// fail the finance transaction that preceded it, and pure-v2 orders (created
// through /api/v1/orders, never mirrored) are left untouched.
// REMOVAL PATH (Phase G): delete this module and the mirrored collections; the
// app will stream order data from /api/v1/orders only.
const { FieldValue } = require('firebase-admin/firestore');
const { getFirebaseFirestore } = require('../../config/firebase');
const { legacyStatusOf } = require('./legacy-status');

// Default instance wired to the real Firestore (no-op when unconfigured).
async function syncLegacyOrderStatus(order) {
  const sync = buildSyncLegacyOrderStatus(getFirebaseFirestore());
  await sync(order);
}

// Test seam: accepts an injectable firestore so unit tests can assert exact
// write behaviour (or the absence of writes) without real credentials.
function buildSyncLegacyOrderStatus(db) {
  return async function syncFromDb(order) {
    try {
      if (!db) return;
      // Only touch docs that already exist — mirroring is for app/web orders
      // that were mirrored at creation, never for pure-v2 orders.
      const snapshot = await db.collection('orders').doc(order.id).get();
      if (!snapshot.exists) return;
      const patch = { status: legacyStatusOf(order.status), updatedAt: FieldValue.serverTimestamp() };
      await db.collection('orders').doc(order.id).set(patch, { merge: true });
      await db.collection('transactions').doc(order.id).set(patch, { merge: true });
    } catch (e) {
      console.error('[SYNC] Firestore status mirror failed:', e.message);
    }
  };
}

module.exports = {
  syncLegacyOrderStatus,
  buildSyncLegacyOrderStatus,
};