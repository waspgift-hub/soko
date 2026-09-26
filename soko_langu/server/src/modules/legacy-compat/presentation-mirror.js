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
      // The current Flutter seller/buyer surfaces still stream Firestore.
      // Create a presentation document for every v1 order so the UI and the
      // authoritative Postgres lifecycle cannot diverge during the bridge.
      const patch = {
        status: legacyStatusOf(order.status),
        orderId: order.id,
        buyerId: order.buyer?.firebaseUid || order.buyerId,
        sellerId: order.seller?.userId || order.sellerId,
        productPrice: Number(order.productPrice || 0),
        shippingCost: Number(order.shippingFee || 0),
        platformFee: Number(order.platformCommission || 0),
        totalAmount: Number(order.totalAmount || 0),
        productName: order.productSnapshot?.title || '',
        productImage: order.productSnapshot?.imageUrl || '',
        buyerName: order.buyer?.displayName || '',
        sellerName: order.seller?.storeName || '',
        shippingQuote: order.shippingQuoteSnapshot || null,
        updatedAt: FieldValue.serverTimestamp(),
      };
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