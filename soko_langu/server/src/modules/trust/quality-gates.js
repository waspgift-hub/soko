const { getPrisma } = require('../../config/database');

const GATE_THRESHOLDS = {
  highRiskSellerScore: 30,      // reliabilityScore below this => high risk (0-1 scale)
  maxNewSellerProducts: 5,      // unverified sellers limited product count
  listingPhotoMin: 2,           // high-value listings require N photos
  highValueLimit: 500000,       // TZS above which stricter gates apply
};

/**
 * Evaluate quality gates before a seller can gain full distribution.
 * Returns { allowed, gates, reasons }.
 */
async function evaluateQualityGates({ sellerId, productId }) {
  const prisma = getPrisma();
  const seller = await prisma.sellerProfile.findUnique({
    where: { id: sellerId },
    include: { products: true },
  });
  if (!seller) throw httpError(404, 'SELLER_NOT_FOUND');

  const gates = [];
  const reasons = [];

  // Identity verification gate
  if (seller.verificationStatus !== 'verified') {
    gates.push('IDENTITY_VERIFICATION');
    reasons.push('Seller identity not verified');
  }

  // High-risk reliability gate
  if (Number(seller.reliabilityScore) < GATE_THRESHOLDS.highRiskSellerScore) {
    gates.push('RELIABILITY_SCORE');
    reasons.push('Seller reliability score below threshold');
  }

  // New seller product cap
  if (seller.verificationStatus !== 'verified' && seller.products.length >= GATE_THRESHOLDS.maxNewSellerProducts) {
    gates.push('NEW_SELLER_PRODUCT_CAP');
    reasons.push('New seller listing cap reached');
  }

  // High-value listing photo gate
  if (productId) {
    const product = await prisma.product.findUnique({
      where: { id: productId },
      include: { media: true },
    });
    if (product && product.price > BigInt(GATE_THRESHOLDS.highValueLimit)) {
      if (product.media.length < GATE_THRESHOLDS.listingPhotoMin) {
        gates.push('HIGH_VALUE_PHOTOS');
        reasons.push('High-value listing requires more photos');
      }
    }
  }

  // Any block is a hard stop for full distribution; verify-seller can bypass some.
  const previousNewSellerGates = ['NEW_SELLER_PRODUCT_CAP'];
  const blocking = gates.filter((g) => !(previousNewSellerGates.includes(g) && seller.verificationStatus === 'verified'));

  return {
    allowed: blocking.length === 0,
    gates,
    blocking,
    reasons,
  };
}

function httpError(status, message) {
  const e = new Error(message);
  e.status = status;
  return e;
}

module.exports = { GATE_THRESHOLDS, evaluateQualityGates };
