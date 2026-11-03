/**
 * Money math helpers shared between index.js and tests.
 * Kept side-effect free (no Firestore imports, no env reads) so the pricing,
 * fee and flash-sale money rules can be unit-tested without a live database.
 */

/** Parse flash sale end/start time from Firestore Timestamp, ISO string, seconds, or legacy field names. */
function parseFlashSaleEndTime(data) {
  const raw = data?.endTime ?? data?.muda_wa_kuisha ?? data?.end_time;
  if (!raw) return null;
  if (raw.toDate && typeof raw.toDate === 'function') return raw.toDate();
  if (raw._seconds != null) return new Date(raw._seconds * 1000);
  if (raw.seconds != null) return new Date(raw.seconds * 1000);
  if (typeof raw === 'number') {
    // Treat values < 1e12 as seconds since epoch.
    return new Date(raw < 1e12 ? raw * 1000 : raw);
  }
  const parsed = new Date(raw);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function isFlashSaleStillActive(data, now = new Date()) {
  const end = parseFlashSaleEndTime(data);
  if (!end) return false;
  return end > now;
}

/**
 * Resolve the price the buyer should actually be charged for a product.
 * When an active flash sale exists for the product, the discounted salePrice
 * wins over whatever the client sent, so the platform commission (and the
 * amount the buyer pays) is always based on the real sale price, never the
 * stale full price from the checkout screen.
 *
 * SECURITY: If no flash sale, the server price from the product document is
 * always used — client-supplied price is only a fallback when the product
 * doc is unreachable (network error), preventing payment tampering.
 *
 * `flashSalesQuery` is injectable for tests; defaults to a Firestore query.
 */
async function resolveEffectivePrice(db, productId, clientPrice, flashSalesQuery) {
  const exec = async () => {
    const query = flashSalesQuery
      ? flashSalesQuery()
      : db.collection('flash_sales')
          .where('productId', '==', productId)
          .where('isActive', '==', true)
          .limit(1);
    return query.get();
  };
  try {
    const snap = await exec();
    if (!snap.empty) {
      const fs = snap.docs[0].data();
      if (isFlashSaleStillActive(fs) && Number(fs.salePrice) > 0) {
        return Math.round(Number(fs.salePrice));
      }
    }
  } catch (e) {
    console.error('resolveEffectivePrice error:', e.message);
  }
  // SECURITY: always trust the server price over client input
  try {
    const productDoc = await db.collection('products').doc(productId).get();
    if (productDoc.exists) {
      const serverPrice = Number(productDoc.data().price);
      if (serverPrice > 0) return Math.round(serverPrice);
    }
  } catch (e) {
    console.error('resolveEffectivePrice: product doc fetch failed, using client price:', e.message);
  }
  return Math.round(Number(clientPrice));
}

module.exports = {
  parseFlashSaleEndTime,
  isFlashSaleStillActive,
  resolveEffectivePrice,
};