const AiProvider = require('./ai-provider');
const { postJson, throwOnError } = require('./upstream');

// Client-facing ids identifyImage sends (groq_service.dart `_visionModel`). They
// are kept in a set so a future vision id is one entry, not a new branch.
const VISION_MODELS = new Set(['llama-3.2-90b-vision-preview']);

/**
 * Cloudflare Workers AI: the failover of last resort for chat, and the second
 * voice backend.
 *
 * Unlike Groq and Gemini this is not a vendor API — it is our own Worker
 * (cf-worker-ai/worker.js) running next to the model on Cloudflare's network.
 * Two consequences shape this class:
 *
 *   - The Cloudflare credential never exists here. This provider holds one
 *     secret, a shared key, which authenticates the Node server to the Worker.
 *     Losing this key costs a redeploy, not a leaked inference credential.
 *   - The Worker speaks OpenAI Chat Completions in and out, so the same
 *     client-facing model id (openai/gpt-oss-120b) resolves on either side and
 *     the tool loop is untouched. Everything Workers AI does differently
 *     (required string `content`, no vision on the mapped models, needing an
 *     explicit tool-call contract) is the Worker's problem, not the gateway's.
 *
 * It sits last in AI_PROVIDER_ORDER on purpose: gpt-oss is the same weight
 * family Groq serves, so this is a like-for-like substitution rather than a
 * quality drop, but Groq is faster and cheaper at equal output.
 */
class CloudflareAiProvider extends AiProvider {
  get name() {
    return 'cloudflare';
  }

  get isConfigured() {
    return Boolean(process.env.CF_AI_URL && process.env.CF_AI_KEY);
  }

  get supportsTranscription() {
    return true;
  }

  /**
   * The model catalogue lives in the Worker (its wrangler.toml vars), not here.
   * One place owns which Workers AI model backs which client-facing id, so
   * retargeting a model is a Worker config change instead of a coordinated
   * edit across the server's env, the Worker and this file.
   */

  /**
   * Text only. The Workers AI vision models take a single flattened prompt
   * string, not the `[{type:'text'},{type:'image_url'}]` content array the app
   * sends, so a vision request here would be answered with the image silently
   * dropped. Gemini is the vision provider and sits ahead of this one, so the
   * practical effect of returning false is that identifyImage keeps its current
   * behaviour instead of acquiring a new way to answer wrongly.
   */
  supportsModel(modelId) {
    return !VISION_MODELS.has(modelId);
  }

  async chat(body, options = {}) {
    if (!this.isConfigured) throw notConfigured(this.name);
    const resp = await postJson(`${baseUrl()}/chat`, {
      headers: {
        'Content-Type': 'application/json',
        'X-AI-Key': process.env.CF_AI_KEY,
      },
      body,
      timeoutMs: options.timeoutMs,
    });
    if (!resp.ok) await throwOnError(resp, this.name);
    return resp.text();
  }

  /**
   * Voice search failover. The Worker takes the same base64 audio Groq gets and
   * hands it to the same Whisper model, so the only thing this adds is a second
   * place for a mic tap to land when Groq is rate limited.
   *
   * `model` is accepted and dropped: the client sends the Groq Whisper id and the
   * Worker maps transcription to its own configured model, same as for chat.
   * The timeout is the shared 10s provider default, unchanged from the Groq
   * path, because the client sets no timeout on this call and would otherwise
   * be left waiting on a slow transcription with nothing to show for it.
   * @param {string} audioBase64 - base64-encoded audio
   * @param {string} language - language code (e.g. 'sw', 'en')
   */
  async transcribe({ audioBase64, model, language }) {
    if (!this.isConfigured) throw notConfigured(this.name);
    const resp = await postJson(`${baseUrl()}/transcribe`, {
      headers: {
        'Content-Type': 'application/json',
        'X-AI-Key': process.env.CF_AI_KEY,
      },
      body: { audio: audioBase64, language },
    });
    if (!resp.ok) await throwOnError(resp, this.name);
    return resp.text();
  }
}

function baseUrl() {
  return String(process.env.CF_AI_URL || '').replace(/\/+$/, '');
}

function notConfigured(providerName) {
  // Not the shared notConfigured() from groq-provider: that one names
  // <PROVIDER>_API_KEY, and the variable an operator actually has to set here is
  // CF_AI_URL/CF_AI_KEY. The code is what routes.js branches on, so only the
  // message differs.
  const e = new Error('CF_AI_URL_AND_CF_AI_KEY_NOT_CONFIGURED');
  e.code = 'AI_NOT_CONFIGURED';
  e.provider = providerName;
  return e;
}

module.exports = CloudflareAiProvider;
module.exports.notConfigured = notConfigured;
