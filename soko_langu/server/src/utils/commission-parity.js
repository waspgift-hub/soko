// Commission parity with the legacy economics: buyers paid the 3.5% platform
// fee ON TOP of price + shipping, plus the ClickPesa USSD push fee as a
// pass-through; sellers netted price + shipping in full. v2 had been
// deducting the fee FROM the seller instead. Keeping sellerEntitlement equal
// to (productPrice + shippingFee) is what makes v2 pay the seller the same
// amount the legacy system would have.
const config = require('../config');
const { getUssdPushFee } = require('../../clickpesa');

function computeSellerParity(productPrice, shippingFee = 0n) {
  const p = BigInt(productPrice);
  const s = BigInt(shippingFee);
  const priceNum = Number(p);
  const percent = config.business.platformCommissionPercent || 0.035;
  const feeTopUp = BigInt(Math.round(priceNum * percent));
  const ussdPassThrough = BigInt(getUssdPushFee(priceNum));
  const commission = feeTopUp + ussdPassThrough;
  const totalAmount = p + s + commission;
  return {
    commission,
    totalAmount,
    sellerEntitlement: totalAmount - commission,
  };
}

module.exports = { computeSellerParity };