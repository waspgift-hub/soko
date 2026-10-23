const GroqProvider = require('./groq-provider');
const GeminiProvider = require('./gemini-provider');
const CloudflareAiProvider = require('./cf-ai-provider');
const { isFailoverWorthy } = require('./upstream');
const { createBreaker } = require('../../utils/circuit-breaker');

// Failover order. Overridable via AI_PROVIDER_ORDER so a region where Groq is
// unreachable can be flipped to Gemini-first with an env change and no deploy.
//
// cloudflare is last because it is our own Worker next to the model rather than a
// vendor API: gpt-oss is the same weight family Groq serves, so it is a
// like-for-like substitution, but Groq is faster and cheaper at equal output.
const DEFAULT_ORDER = ['groq', 'gemini', 'cloudflare'];

const REGISTRY = {
  groq: () => new GroqProvider(),
  gemini: () => new GeminiProvider(),
  cloudflare: () => new CloudflareAiProvider(),
};

const breakers = new Map();
const instances = new Map();

function providerFor(name) {
  if (!instances.has(name)) instances.set(name, REGISTRY[name]());
  return instances.get(name);
}

function breakerFor(name) {
  if (!breakers.has(name)) {
    breakers.set(
      name,
      createBreaker(`ai:${name}`, {
        // Failure threshold inherits the default (5 consecutive).
        //
        // Cooldown is env-tunable because Groq's 429s come with a `retry-after`
        // that routinely exceeds 30s. Probing a half-open circuit before the
        // window resets just burns another rate-limited request, so operators
        // on a free/developer plan should raise this above their typical
        // rate-limit window.
        cooldownMs: breakerCooldownMs(),
      })
    );
  }
  return breakers.get(name);
}

function breakerCooldownMs() {
  const parsed = parseInt(process.env.AI_BREAKER_COOLDOWN_MS, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : undefined;
}

/**
 * Short machine-ish reason for a failure, for operator-facing logs. createBreaker
 * marks open-circuit rejections with `circuitOpen` and no status, so without
 * this the log would read "(error)" / "(undefined)" for the most important case.
 */
function describeError(err) {
  if (!err) return 'unknown';
  if (err.circuitOpen) return 'circuit_open';
  return err.code || err.status || 'error';
}

function providerOrder() {
  const raw = process.env.AI_PROVIDER_ORDER;
  if (!raw) return DEFAULT_ORDER;
  const names = raw
    .split(',')
    .map((s) => s.trim().toLowerCase())
    .filter((s) => REGISTRY[s]);
  return names.length ? names : DEFAULT_ORDER;
}

/**
 * Runs `fn` through a provider's circuit breaker, but only lets FAILOVER-WORTHY
 * errors count toward tripping it.
 *
 * This matters: a 400 (bad request shape) or 401 (revoked key) means the
 * provider is reachable and answering, so the breaker must stay closed —
 * otherwise one malformed client request would push a healthy provider into a
 * 30-second outage for every user.
 */
async function callThroughBreaker(providerName, fn) {
  const breaker = breakerFor(providerName);
  const outcome = await breaker.call(async () => {
    try {
      return { ok: true, value: await fn() };
    } catch (err) {
      if (!isFailoverWorthy(err)) return { ok: false, error: err };
      throw err;
    }
  });
  if (!outcome.ok) throw outcome.error;
  return outcome.value;
}

/**
 * Chat completion with automatic provider failover.
 *
 * Tries each configured provider in AI_PROVIDER_ORDER and hands off on 429 /
 * 5xx / timeout / network error / open circuit. A 4xx (other than 429) is
 * surfaced immediately rather than routed around.
 *
 * @param {object} body OpenAI Chat Completions request from the Flutter client
 * @param {object} [options] forwarded to providers; `timeoutMs` caps a single
 *   call, which the tool loop uses to keep several sequential rounds inside the
 *   client's own 25s wait.
 * @returns {Promise<{ text: string, provider: string, failedOver: boolean }>}
 *   `text` is the provider's raw response body, forwarded to the client as-is.
 */
async function chat(body, options = {}) {
  const attempted = [];
  let lastError = null;
  let hadConfiguredProvider = false;

  for (const name of providerOrder()) {
    const provider = providerFor(name);
    if (!provider.isConfigured) {
      attempted.push(`${name}(unconfigured)`);
      continue;
    }
    if (!provider.supportsModel(body.model)) {
      attempted.push(`${name}(no ${body.model})`);
      continue;
    }
    hadConfiguredProvider = true;

    try {
      const text = await callThroughBreaker(name, () => provider.chat(body, options));
      if (attempted.length) {
        console.warn(
          `[ai] served by ${name} after failover from: ${attempted.join(', ')}`
        );
      }
      return { text, provider: name, failedOver: attempted.length > 0 };
    } catch (err) {
      if (!isFailoverWorthy(err)) {
        // A config/shape bug — trying the next provider cannot help and would
        // only bury the real error.
        throw err;
      }
      console.warn(
        `[ai] ${name} failed (${describeError(err)}): ${err.message}` +
          (err.retryAfter != null ? ` — retry-after ${err.retryAfter}s` : '')
      );
      attempted.push(`${name}(${describeError(err)})`);
      lastError = err;
    }
  }

  if (!hadConfiguredProvider) {
    const e = new Error('AI_NO_PROVIDER_CONFIGURED');
    e.code = 'AI_NO_PROVIDER';
    throw e;
  }
  throw lastError;
}

/**
 * Chat completion as a token stream, with the same provider failover as [chat].
 *
 * Yields `{ type: 'delta', text }` per content chunk and finishes with
 * `{ type: 'done', provider, failedOver, streamed }`.
 *
 * The failover rule is deliberately asymmetric, and it is the one place the
 * streaming path differs from the buffered one:
 *
 *   - Failure BEFORE the first delta is invisible to the user, so it fails over
 *     to the next provider exactly like [chat] would. No text has been shown, so
 *     there is nothing to retract.
 *   - Failure AFTER the first delta cannot fail over. The client has already
 *     rendered half an answer; restarting on another provider would either
 *     duplicate that text or produce a visibly incoherent answer stitched from
 *     two models. Instead the partial text is kept, the failure is yielded as
 *     `{ type: 'error' }`, and the chat store marks the message `failed` — so the
 *     user has a complete partial answer and a retry button rather than a
 *     corrupt transcript.
 *
 * A provider that cannot stream (Cloudflare Workers AI) is still eligible: its
 * single buffered body is re-emitted as one delta, so failover works and the
 * caller cannot tell the difference apart from a very fast model.
 */
async function* chatStream(body, options = {}) {
  const attempted = [];
  let lastError = null;
  let hadConfiguredProvider = false;

  for (const name of providerOrder()) {
    const provider = providerFor(name);
    if (!provider.isConfigured) {
      attempted.push(`${name}(unconfigured)`);
      continue;
    }
    if (!provider.supportsModel(body.model)) {
      attempted.push(`${name}(no ${body.model})`);
      continue;
    }
    hadConfiguredProvider = true;

    let emitted = false;
    try {
      if (!provider.supportsStreaming) {
        // Buffered fallback: one round trip, whole answer at once.
        const buffered = await callThroughBreaker(name, () => provider.chat(body, options));
        const text = extractContent(buffered.text);
        if (text) {
          emitted = true;
          yield { type: 'delta', text };
        }
        if (attempted.length) {
          console.warn(`[ai] streamed-by ${name} after failover from: ${attempted.join(', ')}`);
        }
        yield {
          type: 'done',
          provider: name,
          failedOver: attempted.length > 0,
          streamed: false,
        };
        return;
      }

      const stream = provider.stream(body, options);
      for await (const text of stream) {
        emitted = true;
        yield { type: 'delta', text };
      }
      if (attempted.length) {
        console.warn(`[ai] streamed by ${name} after failover from: ${attempted.join(', ')}`);
      }
      yield {
        type: 'done',
        provider: name,
        failedOver: attempted.length > 0,
        streamed: true,
      };
      return;
    } catch (err) {
      if (!isFailoverWorthy(err)) {
        // A request-shape or credential bug. Handing this to another provider
        // would only hide the real error, exactly as in [chat].
        yield { type: 'error', message: err.message, code: err.code || null };
        return;
      }

      if (emitted) {
        console.warn(`[ai] ${name} stream failed mid-answer: ${err.message}`);
        yield { type: 'error', message: err.message, code: err.code || null, partial: true };
        return;
      }

      console.warn(
        `[ai] ${name} failed to start a stream (${describeError(err)}): ${err.message}` +
          (err.retryAfter != null ? ` — retry-after ${err.retryAfter}s` : '')
      );
      attempted.push(`${name}(${describeError(err)})`);
      lastError = err;
    }
  }

  if (!hadConfiguredProvider) {
    yield { type: 'error', code: 'AI_NO_PROVIDER', message: 'No AI provider configured' };
    return;
  }
  yield {
    type: 'error',
    code: lastError?.code || 'AI_STREAM_FAILED',
    message: lastError?.message || 'AI stream failed',
  };
}

/** Pulls `choices[0].message.content` out of a buffered provider body. */
function extractContent(rawText) {
  try {
    const parsed = JSON.parse(rawText);
    const content = parsed?.choices?.[0]?.message?.content;
    return typeof content === 'string' ? content : '';
  } catch {
    // A non-JSON body is passed through verbatim rather than discarded, matching
    // the buffered [chat] path which also forwards the provider's text as-is.
    return typeof rawText === 'string' ? rawText : '';
  }
}

/**
 * Speech-to-text, with the same failover semantics as [chat].
 *
 * Historically Groq-only, because Gemini's OpenAI-compatible surface exposes no
 * audio/transcriptions endpoint and there was no second backend to hand off to.
 * Workers AI serves the same Whisper model, so voice search now survives a Groq
 * rate limit instead of failing the mic tap outright.
 */
async function transcribe({ audioBase64, model, language }) {
  const attempted = [];
  let lastError = null;
  let hadConfiguredProvider = false;

  for (const name of providerOrder()) {
    const provider = providerFor(name);
    if (!provider.isConfigured) {
      attempted.push(`${name}(unconfigured)`);
      continue;
    }
    if (!provider.supportsTranscription) continue;
    hadConfiguredProvider = true;

    try {
      const text = await callThroughBreaker(name, () =>
        provider.transcribe({ audioBase64, model, language })
      );
      if (attempted.length) {
        console.warn(
          `[ai] transcribed by ${name} after failover from: ${attempted.join(', ')}`
        );
      }
      return text;
    } catch (err) {
      if (!isFailoverWorthy(err)) throw err;
      console.warn(
        `[ai] ${name} transcription failed (${describeError(err)}): ${err.message}`
      );
      attempted.push(`${name}(${describeError(err)})`);
      lastError = err;
    }
  }

  if (!hadConfiguredProvider) {
    const e = new Error('AI_NO_TRANSCRIPTION_PROVIDER_CONFIGURED');
    e.code = 'AI_NO_PROVIDER';
    throw e;
  }
  throw lastError;
}

/** Provider names and configuration state, for boot-time logging. */
function status() {
  return providerOrder().map((name) => ({
    name,
    configured: providerFor(name).isConfigured,
    breaker: breakerFor(name).state,
  }));
}

module.exports = { chat, chatStream, transcribe, status, isFailoverWorthy };
