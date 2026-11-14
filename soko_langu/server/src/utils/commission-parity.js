const config = require('../config');

// Buyer-pays-top commission (Terms 8.2): the platform fee is charged on the
// item subtotal only — never on shipping — and is added to what the buyer pays.
// The seller still nets the item price plus shipping in full, which is the
// invariant escrow-release relies on when it computes
// `sellerReceives = totalAmount - platformCommission`.
function normalizeRate(rate) {
  const n = Number(rate);
  if (!Number.isFinite(n) || n < 0) return 0;
  // The admin field is labelled "(%)", so accept both 3.5 and 0.035.
  if (n > 1) return n <= 100 ? n / 100 : 0;
  return n;
}

// Configured fraction (0.035 = 3.5%). Read at call time so an env override is
// honoured without reloading the module.
function platformRate() {
  return normalizeRate(config.business.platformCommissionPercent);
}

function calcCommission(productPrice, rate = platformRate()) {
  return Math.round(Number(productPrice) * normalizeRate(rate));
}

function computeSellerParity(productPrice, shippingFee = 0n, rate = platformRate()) {
  const p = BigInt(productPrice);
  const s = BigInt(shippingFee);
  const commission = BigInt(calcCommission(p, rate));
  const totalAmount = p + s + commission;
  return {
    commission,
    totalAmount,
    sellerEntitlement: totalAmount - commission,
  };
}

module.exports = { calcCommission, computeSellerParity };
