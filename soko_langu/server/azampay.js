const azampay = require('./src/modules/payments/azampay-provider');

async function azampayCollect({ amount, orderReference, phoneNumber, callbackUrl }) {
  return azampay.initiateCollection({ amount, orderReference, phoneNumber, callbackUrl });
}

async function azampayPaymentStatus(orderReference) {
  return azampay.queryCollectionStatus(orderReference);
}

async function azampayPayout({ amount, orderReference, phoneNumber }) {
  return azampay.initiatePayout({ amount, orderReference, phoneNumber });
}

async function azampayPayoutPreview({ amount, orderReference, phoneNumber }) {
  // AzamPay does not expose a separate preview endpoint in the confirmed contract.
  // Return the net preview instead of calling the gateway.
  return {
    amount: Number(amount),
    fee: 0,
    netAmount: Number(amount),
    recipientPhone: phoneNumber,
    provider: 'azampay',
  };
}

async function azampayUssdPushPreview({ amount, orderReference, phoneNumber }) {
  return azampayPayoutPreview({ amount, orderReference, phoneNumber });
}

async function azampayBalance() {
  return azampay.getBalance();
}

async function azampayRawBalances() {
  const raw = await azampay.getBalance();
  return [{ currency: 'TZS', balance: Number(raw || 0) }];
}

async function azampayQueryPayments(filters = {}) {
  // AzamPay contract: no confirmed /payments/all listing yet. Fail closed.
  throw new Error('AZAMPAY_QUERY_PAYMENTS_NOT_CONFIRMED');
}

async function azampayQueryPayouts(filters = {}) {
  throw new Error('AZAMPAY_QUERY_PAYOUTS_NOT_CONFIRMED');
}

async function azampayCreateBillPayOrder({ billAmount, billDescription, billPaymentMode, billReference }) {
  // AzamPay has no direct BillPay/control-number equivalent. Fail closed so the
  // caller surfaces a clear error instead of inventing a control number.
  throw new Error('AZAMPAY_BILLPAY_NOT_SUPPORTED');
}

function canonicalize(obj) {
  if (obj === null || typeof obj !== 'object') return obj;
  if (Array.isArray(obj)) return obj.map(canonicalize);
  return Object.keys(obj)
    .sort()
    .reduce((acc, key) => {
      acc[key] = canonicalize(obj[key]);
      return acc;
    }, {});
}

function createPayloadChecksum(payload) {
  const key = process.env.AZAMPAY_CHECKSUM_KEY || process.env.AZAMPAY_WEBHOOK_SECRET;
  if (!key) throw new Error('AZAMPAY_CHECKSUM_KEY is not configured');
  const canonicalPayload = canonicalize(payload);
  const payloadString = JSON.stringify(canonicalPayload);
  return require('crypto').createHmac('sha256', key).update(payloadString).digest('hex');
}

// AzamPay fee structure (same bands as ClickPesa's measured USSD-push range,
// since AzamPay's published pricing matches the same MNO cost structure).
const USSD_PUSH_FEE_TIERS = [
  { min: 500, max: 899, fee: 54 },
  { min: 900, max: 1999, fee: 92 },
  { min: 2000, max: 2999, fee: 124 },
  { min: 3000, max: 3999, fee: 230 },
  { min: 4000, max: 4399, fee: 380 },
  { min: 4400, max: 8999, fee: 580 },
  { min: 9000, max: 19999, fee: 920 },
  { min: 20000, max: 39999, fee: 1150 },
  { min: 40000, max: 49999, fee: 1572 },
  { min: 50000, max: 95999, fee: 2136 },
  { min: 96000, max: 199999, fee: 3240 },
  { min: 200000, max: 299999, fee: 3660 },
  { min: 300000, max: 399999, fee: 4080 },
  { min: 400000, max: 499999, fee: 4340 },
  { min: 500000, max: 599999, fee: 4820 },
  { min: 600000, max: 799999, fee: 5230 },
  { min: 800000, max: 999999, fee: 6146 },
  { min: 1000000, max: 1999999, fee: 7210 },
  { min: 2000000, max: 3000000, fee: 7960 },
];

const PAYOUT_FEE_TIERS = [
  { min: 100, max: 999, fee: 52 },
  { min: 1000, max: 1999, fee: 72 },
  { min: 2000, max: 2999, fee: 104 },
  { min: 3000, max: 3999, fee: 116 },
  { min: 4000, max: 4999, fee: 168 },
  { min: 5000, max: 6999, fee: 234 },
  { min: 7000, max: 7999, fee: 360 },
  { min: 8000, max: 9999, fee: 430 },
  { min: 10000, max: 14999, fee: 642 },
  { min: 15000, max: 19999, fee: 680 },
  { min: 20000, max: 29999, fee: 700 },
  { min: 30000, max: 39999, fee: 980 },
  { min: 40000, max: 49999, fee: 1038 },
  { min: 50000, max: 99999, fee: 1460 },
  { min: 100000, max: 199999, fee: 1868 },
  { min: 200000, max: 299999, fee: 2220 },
  { min: 300000, max: 399999, fee: 3180 },
  { min: 400000, max: 499999, fee: 3764 },
  { min: 500000, max: 599999, fee: 4672 },
  { min: 600000, max: 699999, fee: 5712 },
  { min: 700000, max: 799999, fee: 6560 },
  { min: 800000, max: 899999, fee: 7800 },
  { min: 900000, max: 1000000, fee: 8508 },
  { min: 1000001, max: 3000000, fee: 9346 },
  { min: 3000001, max: 5000000, fee: 9890 },
];

const BILLPAY_PERCENT = 0.01;
const HALOPESA_BILLPAY_PERCENT = 0.02;
const CRDB_BILLPAY_PERCENT = 0.01;
const CRDB_DIRECT_DEBIT_FEE = 2000;

function getUssdPushFee(amount) {
  if (amount < USSD_PUSH_FEE_TIERS[0].min) return 0;
  for (const tier of USSD_PUSH_FEE_TIERS) {
    if (amount >= tier.min && amount <= tier.max) return tier.fee;
  }
  return 7960;
}

function getPayoutFee(amount) {
  if (amount < PAYOUT_FEE_TIERS[0].min) return 0;
  for (const tier of PAYOUT_FEE_TIERS) {
    if (amount >= tier.min && amount <= tier.max) return tier.fee;
  }
  return 9890;
}

function calcBillPayFee(amount) {
  return Math.round(amount * BILLPAY_PERCENT);
}

function calcHaloPesaBillPayFee(amount) {
  return Math.round(amount * HALOPESA_BILLPAY_PERCENT);
}

function calcCrdbBillPayFee(amount) {
  return Math.round(amount * CRDB_BILLPAY_PERCENT);
}

function calcGatewayFee(methodId, amount, provider = '') {
  switch (methodId) {
    case 'wallet':
    case 'wallet_balance':
      return 0;
    case 'ussd_push':
      return getUssdPushFee(amount);
    case 'billpay':
      if (provider === 'halopesa') return calcHaloPesaBillPayFee(amount);
      if (provider === 'crdb' || provider === 'crdb_billpay') return calcCrdbBillPayFee(amount);
      return calcBillPayFee(amount);
    case 'crdb_direct_debit':
      return CRDB_DIRECT_DEBIT_FEE;
    default:
      return getUssdPushFee(amount);
  }
}

module.exports = {
  azampayCollect,
  azampayPaymentStatus,
  azampayPayout,
  azampayPayoutPreview,
  azampayUssdPushPreview,
  azampayBalance,
  azampayRawBalances,
  azampayQueryPayments,
  azampayQueryPayouts,
  azampayCreateBillPayOrder,
  canonicalize,
  createPayloadChecksum,
  // Fee tiers
  USSD_PUSH_FEE_TIERS,
  PAYOUT_FEE_TIERS,
  // Percentage fees
  BILLPAY_PERCENT,
  HALOPESA_BILLPAY_PERCENT,
  CRDB_BILLPAY_PERCENT,
  CRDB_DIRECT_DEBIT_FEE,
  // Fee calculators
  getUssdPushFee,
  getPayoutFee,
  calcUssdFee: getUssdPushFee,
  calcBillPayFee,
  calcHaloPesaBillPayFee,
  calcCrdbBillPayFee,
  calcGatewayFee,
};
