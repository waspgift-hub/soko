// Abstract contract for LLM providers (Groq, Gemini, future OpenAI/Azure).
// Deliberately mirrors server/src/modules/payments/provider-interface.js so the
// AI seam reads like the provider pattern already used for payments.
//
// Every implementation MUST:
//   - return the RAW OpenAI Chat Completions body (a JSON string), never a
//     re-serialized object. The Flutter client parses
//     `choices[0].message.content` in groq_service.dart, so returning Groq's
//     wire format verbatim is what lets Gemini serve as a fallback with zero
//     client changes and no app release.
//   - throw an Error carrying `.provider` and `.status` on upstream failure so
//     ai-gateway can decide whether the error is worth failing over.
//
// Providers read process.env directly rather than src/config: the legacy
// monolith (server/index.js) does not load src/config, and that module throws
// on missing production config at require time. Keeping this module free of it
// means both entrypoints can boot the AI path with no new coupling.

class AiProvider {
  /**
   * Stable provider identifier used in logs, error codes and the
   * X-AI-Provider response header: 'groq' | 'gemini' | ...
   */
  get name() {
    throw new Error('Not implemented');
  }

  /**
   * True when the provider has the credentials it needs. An unconfigured
   * provider is skipped by the gateway instead of being called and failing,
   * which is what keeps a missing GEMINI_API_KEY from turning into a 500.
   */
  get isConfigured() {
    throw new Error('Not implemented');
  }

  /**
   * Whether [transcribe] is implemented. Gemini's OpenAI-compatible surface
   * covers chat only; Groq and the Cloudflare Workers AI Worker both serve
   * Whisper, so voice search has somewhere to fail over to.
   */
  get supportsTranscription() {
    return false;
  }

  /**
   * Whether this provider can serve [modelId], the client-facing model id.
   *
   * The gateway skips a provider that returns false instead of calling it and
   * failing. The case that makes this necessary: the app asks for a vision model
   * (identifyImage sends `llama-3.2-90b-vision-preview`), and a text-only
   * provider handed the same request would have to drop the image and then answer
   * from the remaining prompt — a confident wrong answer instead of an error.
   *
   * @param {string} modelId - model id as sent by the Flutter client
   */
  supportsModel(_modelId) {
    return true;
  }

  /**
   * Runs a chat completion. [body] is an OpenAI Chat Completions request
   * object as sent by the Flutter client ({ model, messages, temperature,
   * max_tokens }).
   *
   * [options.timeoutMs] caps this single call. The tool loop passes the smaller
   * of the provider default and whatever is left of the request's total budget,
   * because three sequential tool rounds at the per-call default can otherwise
   * overrun the 25s the Flutter client waits.
   * @returns {Promise<string>} raw JSON response body
   */
  async chat(body, options = {}) {
    throw new Error('Not implemented');
  }

  /**
   * Transcribes base64-encoded audio.
   * @returns {Promise<string>} raw JSON response body containing `text`
   */
  async transcribe({ audioBase64, model, language }) {
    throw new Error('Not implemented');
  }
}

module.exports = AiProvider;
