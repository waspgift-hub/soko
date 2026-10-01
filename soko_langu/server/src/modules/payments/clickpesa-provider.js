const crypto = require('crypto');
const axios = require('axios');
const config = require('../../config');
const PaymentProvider = require('./provider-interface');
const { createBreaker } = require('../../utils/circuit-breaker');
const { PaymentError } = require('./payment-errors');

// Verified live against the gateway. The .env.example value that used to sit
// here (https://native.clickpesa.com/api) does not resolve at all — it is not a
// slower host, it is a dead name, so anyone who copied the template could not
// authenticate.
const CLICKPESA_BASE_URL = process.env.CLICKPESA_API_URL || 'https://api.clickpesa.com/third-parties';

// Measured against the live gateway, not assumed:
//   400 "Amount must be between 500 and 3000000"
// Checking it here turns an opaque gateway 400 into a message the app can act
// on, and stops a sub-500 order from creating a payment row that can never be
// collected.
const MIN_COLLECTION_AMOUNT = 500;
const MAX_COLLECTION_AMOUNT = 3_000_000;

// Fail fast when ClickPesa is down: 3 consecutive failures open the breaker and
// payment initiation is declined immediately instead of queueing 15s+ timeouts.
const clickPesaBreaker = createBreaker('clickpesa', { failureThreshold: 3 });

// Token cache (JWT expires in 1 hour)
let _token = null;
let _tokenExpiresAt = 0;

async function getToken() {
  if (_token && Date.now() < _tokenExpiresAt) return _token;
  const resp = await axios.post(
    `${CLICKPESA_BASE_URL}/generate-token`,
    {},
    {
      headers: {
        'client-id': process.env.CLICKPESA_CLIENT_ID,
        'api-key': process.env.CLICKPESA_API_KEY,
      },
    }
  );
  _token = resp.data.token;
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
  const key = process.env.CLICKPESA_CHECKSUM_KEY;
  // Fail closed. Returning '' when the key is unset would silently send
  // unsigned requests, and the gateway rejects those with "Invalid checksum" —
  // so the symptom is a payment feature that is mysteriously broken rather than
  // a config error naming the missing variable.
  if (!key) {
    throw new Error('CLICKPESA_CHECKSUM_KEY is not configured');
  }
  const canonicalPayload = canonicalize(payload);
  const payloadString = JSON.stringify(canonicalPayload);
  return crypto.createHmac('sha256', key).update(payloadString).digest('hex');
}

async function api(method, path, body, query) {
  const token = await getToken();
  const finalBody = { ...body };
  if (process.env.CLICKPESA_CHECKSUM_KEY && body && method.toUpperCase() !== 'GET') {
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
  // Route the whole call through the breaker: on OPEN the fallback (null) is
  // returned and the caller decides how to degrade.
  return clickPesaBreaker
    .call(
      async () => {
        try {
          const resp = await axios({
            method,
            url: `${CLICKPESA_BASE_URL}${path}${qs ? `?${qs}` : ''}`,
            data: finalBody,
            headers: { Authorization: token, 'Content-Type': 'application/json' },
            timeout: 15000,
          });
          return resp.data;
        } catch (err) {
          const status = err.response && err.response.status;
          if (status >= 400 && status < 500) {
            // Returned as a value rather than thrown so the breaker does not
            // count it. A 400 "Invalid checksum" or "Amount must be between 500
            // and 3000000" says the gateway is reachable and rejecting us, and
            // counting it would let three bad requests open the circuit and deny
            // payment to every healthy buyer. Re-thrown just below, with the
            // status and the gateway's own message intact.
            return { __gatewayClientError: true, status, data: err.response.data };
          }
          // 5xx, timeouts and socket errors stay thrown: those really do mean
          // the provider is unhealthy and should trip the breaker.
          throw err;
        }
      },
      // Breaker OPEN: surface a 503 so the caller degrades with a clean message
      // instead of crashing on a null provider response.
      () => { const err = new Error('PAYMENT_PROVIDER_UNAVAILABLE'); err.status = 503; throw err; },
    )
    .then((result) => {
      if (result && result.__gatewayClientError) {
        const data = result.data || {};
        const message = (data && (data.message || data.error)) || `ClickPesa rejected the request (${result.status})`;
        const err = new Error(String(message));
        err.status = result.status;
        err.gatewayResponse = data;
        throw err;
      }
      return result;
    });
}

class ClickPesaProvider extends PaymentProvider {
  get name() {
    return 'clickpesa';
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
      // Checked before the gateway call so the app gets a precise, actionable
      // message. ClickPesa answers the same mistake with
      // "Amount must be between 500 and 3000000", which says nothing about
      // WHICH side was wrong and reads like a gateway fault.
      throw new PaymentError({
        code: 'AMOUNT_OUT_OF_RANGE',
        message: `Kiasi ni nje ya masafa: ClickPesa in pokea TZS ${MIN_COLLECTION_AMOUNT.toLocaleString()} - ${MAX_COLLECTION_AMOUNT.toLocaleString()}`,
        provider: this.name,
        status: 400,
      });
    }

    const body = {
      amount: String(value),
      orderReference,
      // ClickPesa rejects "+255..." with "must start with country code and
      // without the plus sign" (verified live), so the number is normalized
      // here rather than trusted from the client.
      phoneNumber: normalizeMsisdn(phoneNumber),
      currency: 'TZS',
    };
    if (callbackUrl) body.callbackUrl = callbackUrl;
    const resp = await api('POST', '/payments/initiate-ussd-push-request', body);
    return {
      providerReference: resp.orderReference || orderReference,
      raw: resp,
    };
  }

  async queryCollectionStatus(orderReference) {
    const raw = await api('GET', `/payments/${encodeURIComponent(orderReference)}`);
    const row = firstRow(raw);
    // A payment the gateway has never heard of. Surfacing it as an empty status
    // used to make every verification answer "PAYMENT_NOT_VERIFIED:" with a
    // blank reason, which is indistinguishable from a pending payment.
    if (!row) {
      throw new PaymentError({
        code: 'PAYMENT_NOT_FOUND',
        message: `ClickPesa haijakubali malipo yenye kumbukumbu ${orderReference}`,
        provider: this.name,
        status: 404,
        providerReference: orderReference,
      });
    }
    return {
      status: normalizeStatus(row.status),
      // Verified live: the gateway's per-payment id looks like "LCPCAH7ZVP75PK"
      // and is echoed back on the webhook, so it is the only handle that ties a
      // stored payment row to a gateway row.
      providerPaymentId: row.id || row.paymentId || null,
      failureReason: typeof row.message === 'string' && row.message.trim() ? row.message.trim() : null,
      raw: row,
    };
  }

  async initiatePayout({ amount, orderReference, phoneNumber }) {
    const resp = await api('POST', '/payouts/create-mobile-money-payout', {
      amount,
      orderReference,
      phoneNumber,
      currency: 'TZS',
    });
    return resp;
  }

  verifyWebhook(payload, signature) {
    const secret = process.env.CLICKPESA_WEBHOOK_SECRET;
    if (!secret) return config.nodeEnv === 'development';
    const expected = createPayloadChecksum(payload);
    if (!signature) {
      // Some ClickPesa webhook payloads carry their own checksum field
      const bodyChecksum = payload && payload.checksum;
      return !!bodyChecksum && safeEqual(bodyChecksum, expected);
    }
    return safeEqual(signature, expected);
  }

  normalizeWebhook(payload) {
    // The gateway's webhook body is the same object its query endpoint returns
    // inside an array, so it goes through the same unwrapping. Without this,
    // payload.status was undefined on every real callback and the webhook
    // handler had no idea whether the customer had paid.
    const row = firstRow(payload) || {};
    return {
      orderReference: row.orderReference || row.order_reference || null,
      providerPaymentId: row.id || row.paymentId || row.payment_id || null,
      amount: row.amount != null ? Number(row.amount) : row.collectedAmount != null ? Number(row.collectedAmount) : null,
      status: normalizeStatus(row.status),
      failureReason: typeof row.message === 'string' && row.message.trim() ? row.message.trim() : null,
      raw: row,
    };
  }
}

/**
 * ClickPesa answers a list query with an ARRAY even when it matches one row:
 *   GET /payments/{orderReference} -> [{ id, status, message, ... }]
 * The old code read `.status` straight off that array, which is undefined, so
 * every verification resolved to an empty status.
 */
function firstRow(raw) {
  if (Array.isArray(raw)) return raw.find((r) => r && typeof r === 'object') || null;
  if (raw && typeof raw === 'object' && Array.isArray(raw.data)) {
    return raw.data.find((r) => r && typeof r === 'object') || null;
  }
  return raw && typeof raw === 'object' && !Array.isArray(raw) && raw.status ? raw : null;
}

/**
 * Mobile-money MSISDN in the form ClickPesa accepts: country code, no plus, no
 * leading zero. Verified live — "+255693273241" and "0693273241" are both
 * rejected with "must start with country code and without the plus sign",
 * while "255693273241" is accepted.
 */
function normalizeMsisdn(phone) {
  const digits = String(phone || '').replace(/\D/g, '');
  if (digits.length < 9) {
    throw new PaymentError({
      code: 'INVALID_PHONE',
      message: 'Namba ya simu si sahihi',
      provider: 'clickpesa',
      status: 400,
    });
  }
  if (digits.startsWith('0')) return `255${digits.slice(1)}`;
  if (digits.startsWith('255')) return digits;
  return `255${digits}`;
}

function normalizeStatus(status) {
  const s = String(status || '').toUpperCase();
  if (['SUCCESS', 'SUCCESSFUL', 'PAID', 'COMPLETED'].includes(s)) return 'completed';
  if (['PENDING', 'INITIATED', 'PROCESSING'].includes(s)) return 'pending';
  if (['FAILED', 'ERROR', 'DECLINED', 'CANCELLED'].includes(s)) return 'failed';
  return s.toLowerCase();
}

function safeEqual(a, b) {
  const bufA = Buffer.from(String(a));
  const bufB = Buffer.from(String(b));
  return bufA.length === bufB.length && crypto.timingSafeEqual(bufA, bufB);
}

module.exports = ClickPesaProvider;
// Exported for tests: the array unwrapping and the MSISDN rules are the two
// pieces of this file that were silently wrong, so they are asserted directly
// rather than only through a mocked HTTP layer.
module.exports.firstRow = firstRow;
module.exports.normalizeMsisdn = normalizeMsisdn;
module.exports.normalizeStatus = normalizeStatus;
module.exports.MIN_COLLECTION_AMOUNT = MIN_COLLECTION_AMOUNT;
module.exports.MAX_COLLECTION_AMOUNT = MAX_COLLECTION_AMOUNT;
