const axios = require('axios');
const crypto = require('crypto');

const CLICKPESA_BASE_URL = 'https://api.clickpesa.com/third-parties';
const CLICKPESA_CLIENT_ID = process.env.CLICKPESA_CLIENT_ID || '';
const CLICKPESA_API_KEY = process.env.CLICKPESA_API_KEY || '';
const CLICKPESA_CHECKSUM_KEY = process.env.CLICKPESA_CHECKSUM_KEY || '';

// Token cache (JWT expires in 1 hour)
let _token = null;
let _tokenExpiresAt = 0;

async function getToken() {
  if (_token && Date.now() < _tokenExpiresAt) return _token;
  const resp = await axios.post(
    `${CLICKPESA_BASE_URL}/generate-token`,
    {},
    { headers: { 'client-id': CLICKPESA_CLIENT_ID, 'api-key': CLICKPESA_API_KEY } },
  );
  _token = resp.data.token;
  _tokenExpiresAt = Date.now() + 55 * 60 * 1000;
  return _token;
}

function canonicalize(obj) {
  if (obj === null || typeof obj !== 'object') return obj;
  if (Array.isArray(obj)) return obj.map(canonicalize);
  return Object.keys(obj).sort().reduce((acc, key) => {
    acc[key] = canonicalize(obj[key]);
    return acc;
  }, {});
}

function createPayloadChecksum(payload) {
  if (!CLICKPESA_CHECKSUM_KEY) return '';
  const canonicalPayload = canonicalize(payload);
  const payloadString = JSON.stringify(canonicalPayload);
  const hmac = crypto.createHmac('sha256', CLICKPESA_CHECKSUM_KEY);
  hmac.update(payloadString);
  return hmac.digest('hex');
}

async function api(method, path, body, query) {
  const token = await getToken();
  const finalBody = { ...body };
  if (CLICKPESA_CHECKSUM_KEY && body && method.toUpperCase() !== 'GET') {
    finalBody.checksum = createPayloadChecksum(finalBody);
  }
  const params = new URLSearchParams();
  if (query) {
    for (const [key, value] of Object.entries(query)) {
      if (value === undefined || value === null || value === '') continue;
      params.append(key, String(value));
    }
  }
  const qs = params.toString();
  const resp = await axios({
    method,
    url: `${CLICKPESA_BASE_URL}${path}${qs ? `?${qs}` : ''}`,
    data: finalBody,
    headers: { Authorization: token, 'Content-Type': 'application/json' },
  });
  return resp.data;
}

// =================================================================
// OFFICIAL CLICKPESA FEE STRUCTURES
// Source: https://clickpesa.com/pricing (retrieved July 2026)
// =================================================================

/// Mobile Money USSD Push — charged to the customer
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

function getUssdPushFee(amount) {
  for (const tier of USSD_PUSH_FEE_TIERS) {
    if (amount >= tier.min && amount <= tier.max) return tier.fee;
  }
  return 7960;
}

/// Mobile Money Payout — charged to business (can be passed to recipient)
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

function getPayoutFee(amount) {
  for (const tier of PAYOUT_FEE_TIERS) {
    if (amount >= tier.min && amount <= tier.max) return tier.fee;
  }
  return 9890;
}

// =================================================================
// PERCENTAGE-BASED FEE HELPERS
// =================================================================

/// BillPay (M-Pesa, Airtel, Tigo) — 1% charged to organization
const BILLPAY_PERCENT = 0.01;

/// BillPay (HaloPesa) — 2% charged to organization
const HALOPESA_BILLPAY_PERCENT = 0.02;

/// CRDB BillPay — 1% charged to organization
const CRDB_BILLPAY_PERCENT = 0.01;

/// CRDB Direct Debit — flat TZS 2,000 charged to organization
const CRDB_DIRECT_DEBIT_FEE = 2000;

// =================================================================
// FEE CALCULATION FUNCTIONS
// =================================================================

function calcUssdFee(amount) {
  return getUssdPushFee(amount);
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

// =================================================================
// ALL PAYMENT METHODS WITH FEE INFO
// =================================================================

const ALL_PAYMENT_METHODS = [
  {
    id: 'wallet',
    name: 'Wallet',
    nameSw: 'Pochi',
    description: 'Pay from your Soko Vibe wallet balance. Deposit first via USSD or BillPay.',
    descriptionSw: 'Lipa kutoka kwenye pochi yako ya Soko Vibe. Weka hela kwanza kwa USSD au BillPay.',
    feeType: 'none',
    feeLabel: 'Free',
    feeLabelSw: 'Bure',
    icon: 'account_balance_wallet',
    color: '#1B5E20',
  },
  {
    id: 'ussd_push',
    name: 'Mobile Money USSD Push',
    nameSw: 'USSD Push (M-Pesa, Tigo, Airtel)',
    description: 'Receive a USSD prompt on your phone. Works with M-Pesa, Airtel Money, Tigo, HaloPesa.',
    descriptionSw: 'Pokea kidokezo cha USSD kwenye simu yako. Inafanya kazi na M-Pesa, Airtel, Tigo, HaloPesa.',
    feeType: 'tiered',
    feeLabel: 'TZS 54 – 7,960',
    feeLabelSw: 'TZS 54 – 7,960',
    tiers: USSD_PUSH_FEE_TIERS,
    icon: 'phone_android',
    color: '#E65100',
  },
  {
    id: 'billpay',
    name: 'BillPay (M-Pesa, Airtel, Tigo)',
    nameSw: 'BillPay (M-Pesa, Airtel, Tigo)',
    description: 'Pay directly via mobile money BillPay. 1% fee.',
    descriptionSw: 'Lipa moja kwa moja kwa BillPay. Ada 1%.',
    feeType: 'percent',
    percent: BILLPAY_PERCENT,
    percentLabel: '1%',
    icon: 'receipt_long',
    color: '#2E7D32',
  },
];

/// Calculate gateway fee for a given payment method and amount
function calcGatewayFee(methodId, amount) {
  switch (methodId) {
    case 'wallet':
      return 0;
    case 'ussd_push':
      return getUssdPushFee(amount);
    case 'billpay':
      return calcBillPayFee(amount);
    default:
      return getUssdPushFee(amount);
  }
}

// =================================================================
// ORIGINAL CLICKPESA API FUNCTIONS (unchanged)
// =================================================================

async function clickpesaCollect({ amount, orderReference, phoneNumber, callbackUrl }) {
  const body = {
    amount: String(amount),
    orderReference,
    phoneNumber,
    currency: 'TZS',
  };
  if (callbackUrl) {
    body.callbackUrl = callbackUrl;
  }
  return api('POST', '/payments/initiate-ussd-push-request', body);
}

async function clickpesaPaymentStatus(orderReference) {
  return api('GET', `/payments/all?orderReference=${encodeURIComponent(orderReference)}`);
}

async function clickpesaPayout({ amount, orderReference, phoneNumber }) {
  return api('POST', '/payouts/create-mobile-money-payout', {
    amount,
    orderReference,
    phoneNumber,
    currency: 'TZS',
  });
}

async function clickpesaPayoutPreview({ amount, orderReference, phoneNumber }) {
  return api('POST', '/payouts/preview-mobile-money-payout', {
    amount,
    orderReference,
    phoneNumber,
    currency: 'TZS',
  });
}

/** Normalizes the ClickPesa balance payload to a TZS amount (number). */
async function clickpesaBalance() {
  const raw = await api('GET', '/account/balance');
  if (typeof raw === 'number') return raw;
  if (raw && typeof raw === 'object' && Array.isArray(raw.balances)) {
    const tzs = raw.balances.find((b) => b && b.currency === 'TZS');
    return Number(tzs?.balance || 0);
  }
  if (raw && typeof raw.balance === 'number') return raw.balance;
  return 0;
}

/** Raw balances array from ClickPesa (all currencies). */
async function clickpesaRawBalances() {
  const raw = await api('GET', '/account/balance');
  if (Array.isArray(raw)) return raw.map((b) => ({ currency: b.currency, balance: Number(b.balance || 0) }));
  if (raw && typeof raw === 'object' && Array.isArray(raw.balances)) {
    return raw.balances.map((b) => ({ currency: b.currency, balance: Number(b.balance || 0) }));
  }
  return [];
}

/** Queries all payments (collections) with optional filters. */
async function clickpesaQueryPayments(filters = {}) {
  return api('GET', '/payments/all', undefined, filters);
}

/** Queries all payouts (disbursements) with optional filters. */
async function clickpesaQueryPayouts(filters = {}) {
  return api('GET', '/payouts/all', undefined, filters);
}

async function clickpesaCreateBillPayOrder({ billAmount, billDescription, billPaymentMode, billReference }) {
  const body = {
    billAmount,
    billDescription: billDescription || 'Soko Vibe payment',
    billPaymentMode: billPaymentMode || 'EXACT',
  };
  if (billReference) {
    body.billReference = billReference;
  }
  return api('POST', '/billpay/create-order-control-number', body);
}

module.exports = {
  // Core API
  clickpesaCollect,
  clickpesaPaymentStatus,
  clickpesaPayout,
  clickpesaPayoutPreview,
  clickpesaBalance,
  clickpesaRawBalances,
  clickpesaQueryPayments,
  clickpesaQueryPayouts,
  clickpesaCreateBillPayOrder,
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
  calcUssdFee,
  calcBillPayFee,
  calcHaloPesaBillPayFee,
  calcCrdbBillPayFee,
  calcGatewayFee,
  // Method list
  ALL_PAYMENT_METHODS,
};
