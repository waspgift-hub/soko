const crypto = require('crypto');
const axios = require('axios');
const config = require('../../config');
const PaymentProvider = require('./provider-interface');

const CLICKPESA_BASE_URL = process.env.CLICKPESA_API_URL || 'https://api.clickpesa.com/third-parties';

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
  if (!key) return '';
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
  const resp = await axios({
    method,
    url: `${CLICKPESA_BASE_URL}${path}${qs ? `?${qs}` : ''}`,
    data: finalBody,
    headers: { Authorization: token, 'Content-Type': 'application/json' },
  });
  return resp.data;
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
    const body = {
      amount: String(amount),
      orderReference,
      phoneNumber,
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
    const resp = await api('GET', `/payments/${encodeURIComponent(orderReference)}`);
    return {
      status: normalizeStatus(resp.status),
      providerPaymentId: resp.id || resp.paymentId || null,
      raw: resp,
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
    return {
      orderReference: payload.orderReference || payload.order_reference || null,
      providerPaymentId: payload.id || payload.paymentId || payload.payment_id || null,
      amount: payload.amount ? Number(payload.amount) : null,
      status: normalizeStatus(payload.status),
      raw: payload,
    };
  }
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
