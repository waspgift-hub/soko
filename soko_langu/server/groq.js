const GROQ_API_KEY = process.env.GROQ_API_KEY || '';
const GROQ_CHAT_URL = 'https://api.groq.com/openai/v1/chat/completions';
const GROQ_TRANSCRIBE_URL = 'https://api.groq.com/openai/v1/audio/transcriptions';

async function groqChat(body) {
  if (!GROQ_API_KEY) {
    throw new Error('GROQ_API_KEY_NOT_CONFIGURED');
  }
  const resp = await fetch(GROQ_CHAT_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${GROQ_API_KEY}`,
    },
    body: JSON.stringify(body),
  });
  const text = await resp.text();
  if (resp.ok) return text;
  const err = new Error(`Groq error: ${resp.status}`);
  err.status = resp.status;
  err.body = text;
  throw err;
}

/**
 * Transcribe audio: client sends base64 audio, server builds multipart for Groq.
 * @param {string} audioBase64 - base64-encoded WAV audio
 * @param {string} model - Whisper model name
 * @param {string} language - language code (e.g. 'sw', 'en')
 */
async function groqTranscribe(audioBase64, model, language) {
  if (!GROQ_API_KEY) {
    throw new Error('GROQ_API_KEY_NOT_CONFIGURED');
  }

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
    `${model || 'whisper-large-v3-turbo'}\r\n`
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

  const resp = await fetch(GROQ_TRANSCRIBE_URL, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${GROQ_API_KEY}`,
      'Content-Type': `multipart/form-data; boundary=${boundary}`,
      'Content-Length': String(totalLength),
    },
    body: Buffer.concat(chunks),
  });

  const text = await resp.text();
  if (resp.ok) return text;
  const err = new Error(`Groq transcribe error: ${resp.status}`);
  err.status = resp.status;
  err.body = text;
  throw err;
}

module.exports = { groqChat, groqTranscribe };
