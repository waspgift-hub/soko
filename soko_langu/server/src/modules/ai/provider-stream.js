// Reads an OpenAI-shaped `text/event-stream` response and yields content deltas.
//
// Kept separate from upstream.js because the two have different jobs: upstream
// owns transport (timeout, status, failover-worthy classification), this owns the
// wire format. Both Groq and Gemini emit byte-identical SSE for chat completions,
// so one reader serves both.
//
// Workers AI is the exception and never reaches here — cf-worker-ai hardcodes
// `stream: false`, so that provider reports supportsStreaming === false and the
// gateway feeds its single JSON body through the fallback path instead.

// An open stream with no bytes for this long is a dead socket, not a slow model.
// Without this the read loop would hang a handler open indefinitely, holding an
// Express response and an upstream connection until the process restarts.
const DEFAULT_IDLE_TIMEOUT_MS = 30_000;

// Providers batch several tokens per frame, so a generous ceiling keeps a
// long-but-healthy answer from tripping the guard on a single slow tool phase.
const MIN_IDLE_TIMEOUT_MS = 5_000;

function idleTimeoutMs(override) {
  const parsed = parseInt(override, 10);
  if (Number.isFinite(parsed) && parsed >= MIN_IDLE_TIMEOUT_MS) return parsed;
  return DEFAULT_IDLE_TIMEOUT_MS;
}

/**
 * Yields `{ text }` deltas from [response] until the provider sends its
 * `[DONE]` sentinel or the stream ends.
 *
 * Frames are accumulated into a buffer and split on the SSE record separator, so
 * a delta arriving split across two TCP chunks is not lost — the naive
 * "split the whole body on \n\n" approach corrupts every multi-byte Swahili
 * answer that straddles a packet boundary.
 *
 * @param {Response} response streaming response with a non-null `body`
 * @param {object} [options]
 * @param {number} [options.idleTimeoutMs]
 * @param {(usage: object|null) => void} [options.onUsage] fires once, with the
 *   final frame's `usage` when the provider chose to report it
 * @returns {AsyncGenerator<string>}
 */
async function* readProviderStream(response, options = {}) {
  const body = response.body;
  if (!body) throw streamError('AI_STREAM_NO_BODY', 503);

  const budget = idleTimeoutMs(options.idleTimeoutMs);
  const decoder = new TextDecoder();
  const reader = body.getReader();
  let buffer = '';

  try {
    while (true) {
      const chunk = await withIdleTimeout(reader.read(), budget);
      if (chunk.done) break;
      buffer += decoder.decode(chunk.value, { stream: true });

      // SSE records are separated by a blank line. Normalise CRLF first so a
      // provider that emits \r\n\r\n is not read as one giant record.
      buffer = buffer.replace(/\r\n/g, '\n');
      let split = buffer.indexOf('\n\n');
      while (split !== -1) {
        const record = buffer.slice(0, split);
        buffer = buffer.slice(split + 2);
        const event = parseRecord(record);
        if (event === DONE) return;
        if (event) yield event.text;
        split = buffer.indexOf('\n\n');
      }
    }

    // A stream that ends without [DONE] still emitted usable text in its final
    // unterminated record; draining it here is what stops the last sentence of an
    // answer being dropped when a provider closes the socket promptly.
    const tail = parseRecord(buffer);
    if (tail && tail !== DONE) yield tail.text;
  } finally {
    // Releasing the lock lets an abandoned stream be cancelled rather than
    // holding its socket until the socket times out on its own.
    try {
      reader.releaseLock();
    } catch {
      // Already errored; the socket is being torn down regardless.
    }
  }
}

const DONE = Symbol('sse-done');

/** Parses one SSE record into `{ text }`, DONE, or null to skip it. */
function parseRecord(record) {
  const trimmed = record.trim();
  if (!trimmed) return null;

  const lines = trimmed.split('\n');
  let data = '';
  for (const line of lines) {
    // Comments (`:` prefixed) are keep-alives; `event:`/`id:`/`retry:` carry no
    // payload we need, so only `data:` accumulates.
    if (line.startsWith('data:')) data += line.slice(5).trim();
  }
  if (!data) return null;
  if (data === '[DONE]') return DONE;

  let payload;
  try {
    payload = JSON.parse(data);
  } catch {
    // A malformed frame is skipped rather than fatal: one garbled delta must not
    // discard the whole answer, and the provider is free to close cleanly after.
    return null;
  }

  if (payload?.error) {
    const e = new Error(payload.error.message || 'Provider stream error');
    e.code = 'AI_STREAM_ERROR';
    e.status = 502;
    e.providerMessage = payload.error.message || null;
    throw e;
  }

  const choice = payload?.choices?.[0];
  const text = choice?.delta?.content;
  return typeof text === 'string' && text.length ? text : null;
}

/**
 * Rejects if [promise] has not settled within [budget].
 *
 * The race is left dangling on the losing branch but its rejection is swallowed,
 * so a late chunk cannot surface as an unhandled rejection after the loop has
 * already thrown its timeout.
 */
function withIdleTimeout(promise, budget) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      reject(streamError(`AI_STREAM_IDLE_${budget}MS`, 504));
    }, budget);
    promise.then(
      (value) => {
        clearTimeout(timer);
        resolve(value);
      },
      (err) => {
        clearTimeout(timer);
        reject(err);
      }
    );
  });
}

function streamError(code, status) {
  const e = new Error(code);
  e.code = code;
  e.status = status;
  return e;
}

module.exports = {
  readProviderStream,
  DEFAULT_IDLE_TIMEOUT_MS,
};