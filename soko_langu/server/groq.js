// Legacy shim for the pre-v2 monolith (server/index.js).
//
// The provider implementation now lives in src/modules/ai so both backends
// share one failover path. Only the Whisper route still comes through here,
// because transcription is Groq-exclusive; /api/ai/chat calls the gateway
// directly. New code should use src/modules/ai/routes.js.
const gateway = require('./src/modules/ai/ai-gateway');

/**
 * Transcribe audio: client sends base64 audio, server builds multipart for Groq.
 * Groq-only — Gemini's OpenAI-compatible surface has no transcriptions endpoint.
 * @param {string} audioBase64 - base64-encoded WAV audio
 * @param {string} model - Whisper model name
 * @param {string} language - language code (e.g. 'sw', 'en')
 */
async function groqTranscribe(audioBase64, model, language) {
  return gateway.transcribe({ audioBase64, model, language });
}

module.exports = { groqTranscribe };
