// Commission parity with the product owner's economics: Soko Vibe charges no
// platform fee and no pass-through on orders — the buyer pays price + shipping
// in full to the escrow and the seller nets price + shipping in full. Whatever
// ClickPesa charges (USSD push at collection, payout fee at payout) is deducted
// by ClickPesa itself, outside Soko Vibe's ledger, so our escrow total always
// equals the seller entitlement exactly.
function computeSellerParity(productPrice, shippingFee = 0n) {
  const p = BigInt(productPrice);
  const s = BigInt(shippingFee);
  const commission = 0n;
  const totalAmount = p + s;
  return {
    commission,
    totalAmount,
    sellerEntitlement: totalAmount - commission,
  };
}

module.exports = { computeSellerParity };