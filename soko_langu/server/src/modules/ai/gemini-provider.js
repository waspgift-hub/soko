const AiProvider = require('./ai-provider');
const { postJson, throwOnError } = require('./upstream');
const { notConfigured } = require('./groq-provider');

// Gemini's OpenAI-compatible surface. Same request/response contract as
// OpenAI Chat Completions, which is precisely why it can stand in for Groq
// without a single line of Dart changing.
const GEMINI_CHAT_URL =
  'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions';

// Defaults are NOT Google's flagship recommendation, and that is deliberate.
//
// Measured on this project's free-tier key (2026-09-27, 8 calls per cell):
//   gemini-3.8-flash        text 1/8 ok, VISION 0/8 ok, median 4019ms
//   gemini-3.5-flash-lite   text 8/8 ok, VISION 8/8 ok, median 1064ms
// 3.8-flash is capacity-starved on the free tier and is a thinking model: it
// burned ~1,180 total tokens to emit 3-8 content tokens, which truncates the
// app's small budgets mid-word. A fallback provider that fails a third of the
// time and returns truncated text is worse than no fallback, so Flash-Lite is
// the default everywhere. Raise via env only if the project is on a paid tier.
const DEFAULT_MODEL = 'gemini-3.5-flash-lite';
const DEFAULT_LITE_MODEL = 'gemini-3.5-flash-lite';
const DEFAULT_VISION_MODEL = 'gemini-3.5-flash-lite';

// A thinking model needs headroom before it will emit anything usable. Measured
// on gemini-3.8-flash, a max_tokens=200 request came back as
// "Hapa kuna muhtasari mf" — cut off mid-word. Any budget below this threshold
// is routed to the non-thinking model so a tight budget can never be consumed
// entirely by internal reasoning.
const MIN_TOKENS_FOR_THINKING = 512;

function thinkingHeadroom() {
  const parsed = parseInt(process.env.GEMINI_MIN_TOKENS_FOR_THINKING, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : MIN_TOKENS_FOR_THINKING;
}

// The Flutter client hardcodes Groq model ids in groq_service.dart, and it has
// no idea Gemini exists. Rather than ship an app release to rename them, map
// the ids it sends onto the Gemini equivalents here. The Lite slot exists
// because the client's own 120b -> 20b fallback is a size-reduction ladder;
// Gemini's analogue is a step down to Flash-Lite.
const GROQ_MODEL_TO_GEMINI = {
  'openai/gpt-oss-120b': () => model('GEMINI_MODEL', DEFAULT_MODEL),
  'openai/gpt-oss-20b': () => model('GEMINI_MODEL_LITE', DEFAULT_LITE_MODEL),
  'llama-3.2-90b-vision-preview': () =>
    model('GEMINI_MODEL_VISION', DEFAULT_VISION_MODEL),
};

function model(envKey, fallback) {
  return process.env[envKey] || fallback;
}

/**
 * Resolves a client-supplied model id to a Gemini model id.
 *
 * Unknown ids (a newer app build, or a hand-rolled request) fall through to the
 * default rather than being forwarded verbatim, since Gemini would 400 on a
 * Groq-prefixed name and 400 is deliberately not failover-worthy.
 *
 * [maxTokens] is the client's budget. When the budget is too small for a
 * thinking model to finish reasoning and still say something, the non-thinking
 * model is used instead — otherwise the answer comes back empty or truncated.
 */
function resolveModel(requested, maxTokens) {
  if (typeof maxTokens === 'number' && maxTokens > 0 && maxTokens < thinkingHeadroom()) {
    return model('GEMINI_MODEL_LITE', DEFAULT_LITE_MODEL);
  }
  const mapper = GROQ_MODEL_TO_GEMINI[requested];
  return mapper ? mapper() : model('GEMINI_MODEL', DEFAULT_MODEL);
}

/**
 * Gemini: fallback LLM provider. Chat completions only — Gemini's
 * OpenAI-compatible surface has no audio/transcriptions endpoint, so voice
 * search has no fallback and stays Groq-exclusive.
 */
class GeminiProvider extends AiProvider {
  get name() {
    return 'gemini';
  }

  get isConfigured() {
    return Boolean(process.env.GEMINI_API_KEY);
  }

  async chat(body, options = {}) {
    if (!this.isConfigured) throw notConfigured(this.name);

    const resp = await postJson(
      process.env.GEMINI_BASE_URL || GEMINI_CHAT_URL,
      {
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${process.env.GEMINI_API_KEY}`,
        },
        // Only `model` is rewritten; messages/temperature/max_tokens pass
        // through unchanged because the compat layer accepts them as-is,
        // including the data-URL image_url shape used by identifyImage.
        //
        // Note: thinking cannot be switched off through this compat layer —
        // reasoning_effort and thinking_config were both measured returning 400
        // or having no effect. Token-budget routing is the only lever available.
        body: { ...body, model: resolveModel(body.model, body.max_tokens) },
        timeoutMs: options.timeoutMs,
      }
    );

    if (!resp.ok) await throwOnError(resp, this.name);
    return resp.text();
  }
}

module.exports = GeminiProvider;
module.exports.resolveModel = resolveModel;
module.exports.GEMINI_CHAT_URL = GEMINI_CHAT_URL;
