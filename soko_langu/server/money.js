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

// AzamPay MNO checkout bands, in whole TZS. The provider adds this to the
// amount we push, so it is a buyer-borne fee and must never be folded into
// `totalAmount` (doing so would charge it twice). Kept server-side so the app
// cannot quote a fee that differs from the provider contract.
const MNO_CHECKOUT_FEE_TIERS = [
  [500, 899, 54], [900, 1999, 92], [2000, 2999, 124], [3000, 3999, 230],
  [4000, 4399, 380], [4400, 8999, 580], [9000, 19999, 920],
  [20000, 39999, 1150], [40000, 49999, 1572], [50000, 95999, 2136],
  [96000, 199999, 3240], [200000, 299999, 3660], [300000, 399999, 4080],
  [400000, 499999, 4340], [500000, 599999, 4820], [600000, 799999, 5230],
  [800000, 999999, 6146], [1000000, 1999999, 7210],
  [2000000, 3000000, 7960],
];

function calcMnoCheckoutFee(amount) {
  const value = Math.round(Number(amount));
  if (!Number.isFinite(value) || value < MNO_CHECKOUT_FEE_TIERS[0][0]) return 0;
  for (const [min, max, fee] of MNO_CHECKOUT_FEE_TIERS) {
    if (value >= min && value <= max) return fee;
  }
  return MNO_CHECKOUT_FEE_TIERS[MNO_CHECKOUT_FEE_TIERS.length - 1][2];
}

// One authoritative pricing record stored with the order. Fee payer is the
// provider contract: AzamPay adds the MNO fee on top of the pushed amount, so
// the buyer bears it and the seller still nets the full item price + shipping.
function buildPricingBreakdown({ productPrice, shippingFee = 0, commission = 0, rate = null, at = new Date() }) {
  const p = Math.max(0, Math.round(Number(productPrice) || 0));
  const s = Math.max(0, Math.round(Number(shippingFee) || 0));
  const c = Math.max(0, Math.round(Number(commission) || 0));
  const gatewayAmount = p + s + c;
  const processingFee = calcMnoCheckoutFee(gatewayAmount);
  return {
    productPrice: p,
    shippingCost: s,
    commission: c,
    processingFee,
    processingFeePayer: 'buyer',
    gatewayAmount,
    buyerTotal: gatewayAmount + processingFee,
    sellerNet: p + s,
    currency: 'TZS',
    commissionRate: rate,
    calculatedAt: at.toISOString(),
  };
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
  calcMnoCheckoutFee,
  buildPricingBreakdown,
  MNO_CHECKOUT_FEE_TIERS,
};
