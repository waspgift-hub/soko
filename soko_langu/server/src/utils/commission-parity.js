// Central commission calculation used by order pricing and seller settlement.
// Current Soko Vibe product rule: 3.5% platform commission on product value.
// Shipping is passed through to the seller and is not commissionable.
// BigInt arithmetic keeps TZS calculations exact.
function computeSellerParity(productPrice, shippingFee = 0n) {
  const p = BigInt(productPrice);
  const s = BigInt(shippingFee);
  if (p < 0n || s < 0n) throw new Error('INVALID_ORDER_AMOUNT');

  // 3.5% = 35/1000. Add 500 before integer division for nearest-TZS rounding.
  const commission = (p * 35n + 500n) / 1000n;
  const totalAmount = p + s;

  return {
    commission,
    totalAmount,
    sellerEntitlement: totalAmount - commission,
  };
}

module.exports = { computeSellerParity };
