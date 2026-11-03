const config = require('./config');

class WhatsAppError extends Error {
  constructor(message, { httpStatus, code, graphCode, retryable = false }) {
    super(message);
    this.name = 'WhatsAppError';
    this.httpStatus = httpStatus;
    this.code = code;
    this.graphCode = graphCode;
    this.retryable = retryable;
  }
}

// Graph error codes are documented at developers.facebook.com/docs/whatsapp/cloud-api/support/error-codes
const GRAPH_ERRORS = {
  190: { httpStatus: 401, code: 'TOKEN_INVALID_OR_EXPIRED', message: 'Access token is invalid or expired' },
  4: { httpStatus: 429, code: 'RATE_LIMITED', message: 'API rate limit reached', retryable: true },
  17: { httpStatus: 429, code: 'RATE_LIMITED', message: 'API rate limit reached', retryable: true },
  80007: { httpStatus: 429, code: 'RATE_LIMITED', message: 'WhatsApp rate limit reached', retryable: true },
  130429: { httpStatus: 429, code: 'RATE_LIMITED', message: 'Message throughput limit reached', retryable: true },
  131030: { httpStatus: 422, code: 'RECIPIENT_NOT_ALLOWED', message: 'Recipient is not in the allowed test list' },
  131026: { httpStatus: 422, code: 'RECIPIENT_NOT_ON_WHATSAPP', message: 'Number cannot receive WhatsApp messages' },
  131047: { httpStatus: 422, code: 'OUTSIDE_24H_WINDOW', message: 'Outside the 24-hour window: send an approved template instead' },
  131051: { httpStatus: 422, code: 'UNSUPPORTED_MESSAGE_TYPE', message: 'Message type is not supported' },
  100: { httpStatus: 400, code: 'INVALID_PARAMETER', message: 'Invalid request parameter' },
};

function fromGraphResponse(status, data) {
  const err = data?.error || {};
  const mapped = GRAPH_ERRORS[err.code];
  if (mapped) {
    return new WhatsAppError(err.message || mapped.message, {
      httpStatus: mapped.httpStatus,
      code: mapped.code,
      graphCode: err.code,
      retryable: Boolean(mapped.retryable),
    });
  }
  const retryable = status === 429 || status >= 500;
  return new WhatsAppError(err.message || `Graph API returned HTTP ${status}`, {
    httpStatus: retryable ? 502 : 422,
    code: retryable ? 'UPSTREAM_UNAVAILABLE' : 'WHATSAPP_API_ERROR',
    graphCode: err.code,
    retryable,
  });
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function graphFetch(url, options, { timeoutMs = 15000 } = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(url, { ...options, signal: controller.signal });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw fromGraphResponse(res.status, data);
    return data;
  } catch (err) {
    if (err instanceof WhatsAppError) throw err;
    throw new WhatsAppError(
      err.name === 'AbortError' ? 'Request to WhatsApp timed out' : 'Could not reach WhatsApp',
      { httpStatus: 502, code: 'UPSTREAM_UNAVAILABLE', retryable: true },
    );
  } finally {
    clearTimeout(timer);
  }
}

function assertConfigured() {
  if (!config.isConfigured) {
    throw new WhatsAppError('USER_ACCESS_TOKEN or PHONE_NUMBER_ID is not set', {
      httpStatus: 503,
      code: 'NOT_CONFIGURED',
    });
  }
}

// Retries only transient failures (rate limits, 5xx, network). Invalid numbers
// and template-required errors are final and never retried.
async function sendText(to, body, { maxAttempts = 3 } = {}) {
  assertConfigured();
  const url = `${config.graphBase}/${config.phoneNumberId}/messages`;
  const payload = {
    messaging_product: 'whatsapp',
    recipient_type: 'individual',
    to,
    type: 'text',
    text: { preview_url: false, body },
  };

  let lastErr;
  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    try {
      const data = await graphFetch(url, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${config.accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(payload),
      });
      return {
        wamid: data.messages?.[0]?.id || null,
        waId: data.contacts?.[0]?.wa_id || null,
      };
    } catch (err) {
      lastErr = err;
      if (!err.retryable || attempt === maxAttempts) break;
      await sleep(500 * 2 ** (attempt - 1));
    }
  }
  throw lastErr;
}

async function checkToken() {
  if (!config.isConfigured) return { configured: false, token: 'missing' };
  try {
    const url = `${config.graphBase}/${config.phoneNumberId}?fields=display_phone_number,verified_name`;
    const data = await graphFetch(url, {
      headers: { Authorization: `Bearer ${config.accessToken}` },
    });
    return {
      configured: true,
      token: 'valid',
      displayPhoneNumber: data.display_phone_number || null,
      verifiedName: data.verified_name || null,
    };
  } catch (err) {
    return {
      configured: true,
      token: err.code === 'TOKEN_INVALID_OR_EXPIRED' ? 'invalid' : 'unknown',
      error: err.message,
    };
  }
}

module.exports = { sendText, checkToken, WhatsAppError };
