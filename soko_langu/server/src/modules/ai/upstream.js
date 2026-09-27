// Shared HTTP plumbing for AI providers: bounded-timeout POSTs and the single
// place that decides whether a provider failure justifies failing over.

const { AbortController } = globalThis;

// Per-provider ceiling. The Flutter client aborts /api/ai/chat at 25s
// (groq_service.dart `_proxyCall`), and a failover is SEQUENTIAL, so two
// providers must both fit inside that budget. 10s x 2 = 20s leaves room for
// Firebase token verification and transit. Raising this risks the app showing
// "check your connection" while the server is still burning a Gemini call.
const DEFAULT_TIMEOUT_MS = 10_000;

function timeoutMs() {
  const parsed = parseInt(process.env.AI_PROVIDER_TIMEOUT_MS, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : DEFAULT_TIMEOUT_MS;
}

/**
 * POSTs JSON with an AbortController-backed timeout.
 *
 * Node's bare fetch has no timeout, so a hung upstream would otherwise keep the
 * request (and its billing) alive until Render's 504 — long after the app gave
 * up on it.
 *
 * @returns {Promise<Response>}
 */
async function postJson(url, { headers, body, timeoutMs: overrideMs }) {
  const budget = overrideMs || timeoutMs();
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), budget);
  try {
    return await fetch(url, {
      method: 'POST',
      headers,
      body: JSON.stringify(body),
      signal: controller.signal,
    });
  } catch (err) {
    throw wrapTransportError(err, budget);
  } finally {
    clearTimeout(timer);
  }
}

/**
 * POSTs a pre-built multipart Buffer with an AbortController-backed timeout.
 * Used for Whisper transcription, which is multipart rather than JSON.
 */
async function postBuffer(url, { headers, body, timeoutMs: overrideMs }) {
  const budget = overrideMs || timeoutMs();
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), budget);
  try {
    return await fetch(url, {
      method: 'POST',
      headers,
      body,
      signal: controller.signal,
    });
  } catch (err) {
    throw wrapTransportError(err, budget);
  } finally {
    clearTimeout(timer);
  }
}

function wrapTransportError(err, budget) {
  if (err.name === 'AbortError' || err.name === 'TimeoutError') {
    const e = new Error(`Upstream timeout after ${budget}ms`);
    e.code = 'AI_TIMEOUT';
    e.status = 504;
    return e;
  }
  // DNS failure, TLS reset, socket hangup: from a failover standpoint these are
  // indistinguishable from a provider 5xx, so normalize to 503.
  const e = new Error(err.message || 'Upstream network failure');
  e.code = 'AI_NETWORK';
  e.status = 503;
  return e;
}

/**
 * Converts a non-2xx upstream response into a thrown Error that keeps the
 * status, the provider's own body, and the rate-limit headers. The body matters:
 * it is the only place quota and rate-limit details are visible. `retry-after`
 * matters because it is the provider telling us when it will accept traffic
 * again — without it we would probe the half-open circuit on a fixed guess.
 */
async function throwOnError(response, providerName) {
  const body = await response.text().catch(() => '');
  const e = new Error(`${providerName} error: ${response.status}`);
  e.status = response.status;
  e.provider = providerName;
  e.body = body;
  e.retryAfter = parseRetryAfter(response.headers?.get?.('retry-after'));
  const detail = parseProviderError(body);
  if (detail) {
    e.providerCode = detail.code;
    e.providerMessage = detail.message;
  }
  throw e;
}

/**
 * Digs the provider's own machine code out of the error body. Groq answers with
 * { error: { message, type, code } } and the `code` is the only reliable signal
 * for cases like a retired model that arrive with an otherwise-cryptic status.
 */
function parseProviderError(body) {
  if (!body) return null;
  try {
    const parsed = JSON.parse(body);
    const err = parsed?.error;
    if (!err) return null;
    return {
      code: typeof err.code === 'string' ? err.code : null,
      message: typeof err.message === 'string' ? err.message : null,
    };
  } catch {
    return null;
  }
}

// Provider codes that mean "I cannot serve THIS MODEL" rather than "your
// request is malformed". Groq uses model_decommissioned for retired ids; the
// others are the equivalent signals other providers use.
const MODEL_UNAVAILABLE_CODES = new Set([
  'model_decommissioned',
  'model_deprecated',
  'model_not_found',
  'model_unsupported',
  'not_found_error',
]);

/**
 * Whether a 400 actually means the model is gone, rather than the request being
 * wrong. Necessary because Groq answers a decommissioned model with a 400 —
 * a status we otherwise treat as a caller bug — and because Groq currently
 * offers NO vision model at all, so the app's identifyImage path can only ever
 * be served by the fallback provider.
 */
function isModelUnavailable(err) {
  if (!err) return false;
  if (err.providerCode && MODEL_UNAVAILABLE_CODES.has(err.providerCode)) return true;
  const message = err.providerMessage || err.body || '';
  return /decommissioned|deprecated|is no longer supported|model .* not (found|available)|retired/i.test(
    String(message)
  );
}

/**
 * Groq sets `retry-after` (seconds) on 429; the other x-ratelimit-* headers are
 * always present but are informational only.
 * @returns {number|null} seconds to wait, or null when absent/unparseable
 */
function parseRetryAfter(raw) {
  if (!raw) return null;
  const seconds = parseInt(raw, 10);
  return Number.isFinite(seconds) && seconds >= 0 ? seconds : null;
}

/**
 * Whether a provider failure should hand off to the next provider.
 *
 * Failover-worthy: 429 (rate limited), 498 (Groq's custom "flex tier at
 * capacity — try again later", which is a capacity problem, not a client bug),
 * any 5xx, timeouts, network failures, an already-open circuit, and a 400 that
 * means the model is gone. All of these mean "this provider cannot serve this
 * request right now".
 *
 * NOT failover-worthy: ordinary 400/401/403/404/413/422. A bad request shape, a
 * missing/revoked API key or an oversized payload is a bug or a config problem
 * that Gemini would not fix, and silently routing around it hides the real error
 * from the operator.
 */
function isFailoverWorthy(err) {
  if (!err) return false;
  if (err.circuitOpen) return true;
  if (err.code === 'AI_TIMEOUT' || err.code === 'AI_NETWORK') return true;
  if (err.code === 'AI_NO_PROVIDER') return false;
  const status = err.status;
  if (!status) return false;
  if (status === 400) return isModelUnavailable(err);
  // 498 is Groq's custom "Flex Tier Capacity Exceeded" — the request was fine,
  // Groq just had no flex capacity. It is a 4xx by number but a capacity signal
  // by meaning, so it must fail over like a 429.
  return status === 429 || status === 498 || status >= 500;
}

module.exports = {
  postJson,
  postBuffer,
  throwOnError,
  isFailoverWorthy,
  isModelUnavailable,
  parseProviderError,
  parseRetryAfter,
  timeoutMs,
  DEFAULT_TIMEOUT_MS,
};
