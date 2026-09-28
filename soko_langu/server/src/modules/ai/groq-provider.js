const AiProvider = require('./ai-provider');
const { postJson, postBuffer, throwOnError } = require('./upstream');

const GROQ_CHAT_URL = 'https://api.groq.com/openai/v1/chat/completions';
const GROQ_TRANSCRIBE_URL = 'https://api.groq.com/openai/v1/audio/transcriptions';
const DEFAULT_TRANSCRIBE_MODEL = 'whisper-large-v3-turbo';

/**
 * Groq: primary LLM provider. Serves both chat completions and Whisper
 * speech-to-text; it is the only provider that can do the latter.
 */
class GroqProvider extends AiProvider {
  get name() {
    return 'groq';
  }

  get isConfigured() {
    return Boolean(process.env.GROQ_API_KEY);
  }

  get supportsTranscription() {
    return true;
  }

  async chat(body, options = {}) {
    if (!this.isConfigured) throw notConfigured(this.name);
    const resp = await postJson(GROQ_CHAT_URL, {
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${process.env.GROQ_API_KEY}`,
      },
      body,
      timeoutMs: options.timeoutMs,
    });
    if (!resp.ok) await throwOnError(resp, this.name);
    return resp.text();
  }

  /**
   * Transcribe audio: client sends base64 audio, server builds multipart for
   * Groq. The multipart is assembled by hand (rather than FormData) so the
   * request is byte-identical to what this endpoint has always sent.
   * @param {string} audioBase64 - base64-encoded WAV audio
   * @param {string} model - Whisper model name
   * @param {string} language - language code (e.g. 'sw', 'en')
   */
  async transcribe({ audioBase64, model, language }) {
    if (!this.isConfigured) throw notConfigured(this.name);

    const audioBuffer = Buffer.from(audioBase64, 'base64');
    const boundary = '----groqProxy' + Date.now();
    const filename = `audio_${Date.now()}.wav`;

    const encode = (s) => Buffer.from(s, 'utf-8');
    const chunks = [];

    chunks.push(encode(
      `--${boundary}\r\n` +
      `Content-Disposition: form-data; name="file"; filename="${filename}"\r\n` +
      `Content-Type: audio/wav\r\n\r\n`
    ));
    chunks.push(audioBuffer);
    chunks.push(encode('\r\n'));
    chunks.push(encode(
      `--${boundary}\r\n` +
      `Content-Disposition: form-data; name="model"\r\n\r\n` +
      `${model || DEFAULT_TRANSCRIBE_MODEL}\r\n`
    ));
    if (language) {
      chunks.push(encode(
        `--${boundary}\r\n` +
        `Content-Disposition: form-data; name="language"\r\n\r\n` +
        `${language}\r\n`
      ));
    }
    chunks.push(encode(
      `--${boundary}\r\n` +
      `Content-Disposition: form-data; name="response_format"\r\n\r\n` +
      `json\r\n` +
      `--${boundary}--\r\n`
    ));

    const totalLength = chunks.reduce((sum, c) => sum + c.length, 0);

    const resp = await postBuffer(GROQ_TRANSCRIBE_URL, {
      headers: {
        Authorization: `Bearer ${process.env.GROQ_API_KEY}`,
        'Content-Type': `multipart/form-data; boundary=${boundary}`,
        'Content-Length': String(totalLength),
      },
      body: Buffer.concat(chunks),
    });

    if (!resp.ok) await throwOnError(resp, this.name);
    return resp.text();
  }
}

function notConfigured(providerName) {
  const e = new Error(`${providerName.toUpperCase()}_API_KEY_NOT_CONFIGURED`);
  e.code = 'AI_NOT_CONFIGURED';
  e.provider = providerName;
  return e;
}

module.exports = GroqProvider;
module.exports.notConfigured = notConfigured;
