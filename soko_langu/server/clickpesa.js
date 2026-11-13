// Compatibility names for callers that still say "clickpesa".
// Every function is the AzamPay adapter. This file is not a second gateway.
const azampay = require('./azampay');

module.exports = {
  ...azampay,
  clickpesaCollect: azampay.azampayCollect,
  clickpesaPaymentStatus: azampay.azampayPaymentStatus,
  clickpesaCreateBillPayOrder: azampay.azampayCreateBillPayOrder,
  clickpesaUssdPushPreview: azampay.azampayUssdPushPreview,
  clickpesaBalance: azampay.azampayBalance,
  clickpesaRawBalances: azampay.azampayRawBalances,
  clickpesaQueryPayments: azampay.azampayQueryPayments,
  clickpesaQueryPayouts: azampay.azampayQueryPayouts,
  calcGatewayFee: azampay.calcGatewayFee,
};
