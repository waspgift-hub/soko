const crypto = require('crypto');
const axios = require('axios');
const config = require('../../config');
const PaymentProvider = require('./provider-interface');
const { createBreaker } = require('../../utils/circuit-breaker');
const { PaymentError } = require('./payment-errors');

// AzamPay — replaces ClickPesa entirely.
// Auth: POST /AppRegistration/GenerateToken { appName, clientId, clientSecret } -> token.
// Sandbox auth base: https://authenticator-sandbox.azampay.co.tz
// Sandbox checkout base: https://sandbox.azampay.co.tz
// Production bases must be set via env (AZAMPAY_AUTH_BASE / AZAMPAY_API_BASE)
// and KYC completed in the AzamPay portal before live traffic.
//
// Provider name exposed to the rest of the system: 'azampay'.
const AZAMPAY_BASE_URL = process.env.AZAMPAY_API_BASE || 'https://sandbox.azampay.co.tz/azampay';
const AZAMPAY_AUTH_BASE = process.env.AZAMPAY_AUTH_BASE || 'https://authenticator-sandbox.azampay.co.tz';

const MIN_COLLECTION_AMOUNT = 500;
const MAX_COLLECTION_AMOUNT = 3_000_000;

const azamPayBreaker = createBreaker('azampay', { failureThreshold: 3 });

let _token = null;
let _tokenExpiresAt = 0;

async function getToken() {
  if (_token && Date.now() < _tokenExpiresAt) return _token;
  const resp = await axios.post(
    `${AZAMPAY_AUTH_BASE}/AppRegistration/GenerateToken`,
    {
      appName: process.env.AZAMPAY_APP_NAME,
      clientId: process.env.AZAMPAY_CLIENT_ID,
      clientSecret: process.env.AZAMPAY_CLIENT_SECRET,
    },
    { headers: { 'Content-Type': 'application/json' }, timeout: 15000 },
  );
  const data = resp.data || {};
  // Token lives under several possible keys depending on the AzamPay tenant;
  // accept the most common ones instead of guessing.
  _token = data.token || data.accessToken || data.access_token || data.sessionToken || null;
  if (!_token) {
    const err = new Error('AZAMPAY token missing from GenerateToken response');
    err.status = 502;
    throw err;
  }
  _tokenExpiresAt = Date.now() + 55 * 60 * 1000;
  return _token;
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
  if (!key) {
    throw new Error('AZAMPAY_CHECKSUM_KEY (or AZAMPAY_WEBHOOK_SECRET) is not configured');
  }
  const canonicalPayload = canonicalize(payload);
  const payloadString = JSON.stringify(canonicalPayload);
  return crypto.createHmac('sha256', key).update(payloadString).digest('hex');
}

function normalizeMsisdn(phone) {
  const digits = String(phone || '').replace(/\D/g, '');
  if (digits.length < 9) {
    throw new PaymentError({
      code: 'INVALID_PHONE',
      message: 'Namba ya simu si sahihi',
      provider: 'azampay',
      status: 400,
    });
  }
  if (digits.startsWith('0')) return `255${digits.slice(1)}`;
  if (digits.startsWith('255')) return digits;
  return `255${digits}`;
}

function normalizeStatus(status) {
  const s = String(status || '').toUpperCase();
  if (['SUCCESS', 'SUCCESSFUL', 'PAID', 'COMPLETED', 'SETTLED'].includes(s)) return 'completed';
  if (['PENDING', 'INITIATED', 'PROCESSING', 'AWAITING'].includes(s)) return 'pending';
  if (['FAILED', 'ERROR', 'DECLINED', 'CANCELLED', 'EXPIRED', 'REJECTED'].includes(s)) return 'failed';
  return s.toLowerCase();
}

function safeEqual(a, b) {
  const bufA = Buffer.from(String(a));
  const bufB = Buffer.from(String(b));
  return bufA.length === bufB.length && crypto.timingSafeEqual(bufA, bufB);
}

async function api(method, path, body, query) {
  const token = await getToken();
  const finalBody = { ...body };
  if (process.env.AZAMPAY_CHECKSUM_KEY && body && method.toUpperCase() !== 'GET') {
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
  return azamPayBreaker
    .call(
      async () => {
        try {
          const resp = await axios({
            method,
            url: `${AZAMPAY_BASE_URL}${path}${qs ? `?${qs}` : ''}`,
            data: finalBody,
            headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
            timeout: 15000,
          });
          return resp.data;
        } catch (err) {
          const status = err.response && err.response.status;
          if (status >= 400 && status < 500) {
            return { __gatewayClientError: true, status, data: err.response.data };
          }
          throw err;
        }
      },
      () => { const err = new Error('PAYMENT_PROVIDER_UNAVAILABLE'); err.status = 503; throw err; },
    )
    .then((result) => {
      if (result && result.__gatewayClientError) {
        const data = result.data || {};
        const message = (data && (data.message || data.error)) || `AzamPay rejected the request (${result.status})`;
        const err = new Error(String(message));
        err.status = result.status;
        err.gatewayResponse = data;
        throw err;
      }
      return result;
    });
}

class AzamPayProvider extends PaymentProvider {
  get name() {
    return 'azampay';
  }

  async getBalance() {
    const raw = await api('GET', '/account/balance');
    if (typeof raw === 'number') return raw;
    if (raw && typeof raw === 'object' && Array.isArray(raw.balances)) {
      const tzs = raw.balances.find((b) => b && b.currency === 'TZS');
      return Number(tzs?.balance || 0);
    }
    if (raw && typeof raw.balance === 'number') return raw.balance;
    return 0;
  }

  async initiateCollection({ amount, orderReference, phoneNumber, callbackUrl }) {
    const value = Number(amount);
    if (!Number.isFinite(value) || value < MIN_COLLECTION_AMOUNT || value > MAX_COLLECTION_AMOUNT) {
      throw new PaymentError({
        code: 'AMOUNT_OUT_OF_RANGE',
        message: `Kiasi ni nje ya masafa: AzamPay in pokea TZS ${MIN_COLLECTION_AMOUNT.toLocaleString()} - ${MAX_COLLECTION_AMOUNT.toLocaleString()}`,
        provider: this.name,
        status: 400,
      });
    }

    const body = {
      accountNumber: normalizeMsisdn(phoneNumber),
      amount: String(value),
      currency: 'TZS',
      externalId: orderReference,
      provider: 'Airtel',
    };
    if (callbackUrl) body.callbackUrl = callbackUrl;

    const resp = await api('POST', '/mno/checkout', body);
    return {
      providerReference: resp.externalId || resp.orderReference || orderReference,
      raw: resp,
    };
  }

  async queryCollectionStatus(orderReference) {
    const raw = await api('GET', `/payments/${encodeURIComponent(orderReference)}`);
    const row = firstRow(raw);
    if (!row) {
      throw new PaymentError({
        code: 'PAYMENT_NOT_FOUND',
        message: `AzamPay haijakubali malipo yenye kumbukumbu ${orderReference}`,
        provider: this.name,
        status: 404,
        providerReference: orderReference,
      });
    }
    return {
      status: normalizeStatus(row.status),
      providerPaymentId: row.id || row.paymentId || null,
      failureReason: typeof row.message === 'string' && row.message.trim() ? row.message.trim() : null,
      raw: row,
    };
  }

  async initiatePayout({ amount, orderReference, phoneNumber }) {
    const resp = await api('POST', '/disbursement/create-mobile-money-payout', {
      amount,
      orderReference,
      phoneNumber: normalizeMsisdn(phoneNumber),
      currency: 'TZS',
    });
    return resp;
  }

  verifyWebhook(payload, signature) {
    const secret = process.env.AZAMPAY_WEBHOOK_SECRET || process.env.AZAMPAY_CHECKSUM_KEY;
    if (!secret) return false;
    const expected = createPayloadChecksum(payload);
    if (!signature) {
      const bodyChecksum = payload && payload.checksum;
      return !!bodyChecksum && safeEqual(bodyChecksum, expected);
    }
    return safeEqual(signature, expected);
  }

  normalizeWebhook(payload) {
    const row = firstRow(payload) || {};
    return {
      orderReference: row.orderReference || row.externalId || row.order_reference || null,
      providerPaymentId: row.id || row.paymentId || row.payment_id || null,
      amount: row.amount != null ? Number(row.amount) : row.collectedAmount != null ? Number(row.collectedAmount) : null,
      status: normalizeStatus(row.status),
      failureReason: typeof row.message === 'string' && row.message.trim() ? row.message.trim() : null,
      raw: row,
    };
  }
}

function firstRow(raw) {
  if (Array.isArray(raw)) return raw.find((r) => r && typeof r === 'object') || null;
  if (raw && typeof raw === 'object' && Array.isArray(raw.data)) {
    return raw.data.find((r) => r && typeof r === 'object') || null;
  }
  return raw && typeof raw === 'object' && !Array.isArray(raw) && raw.status ? raw : null;
}

module.exports = AzamPayProvider;
module.exports.firstRow = firstRow;
module.exports.normalizeMsisdn = normalizeMsisdn;
module.exports.normalizeStatus = normalizeStatus;
module.exports.MIN_COLLECTION_AMOUNT = MIN_COLLECTION_AMOUNT;
module.exports.MAX_COLLECTION_AMOUNT = MAX_COLLECTION_AMOUNT;
