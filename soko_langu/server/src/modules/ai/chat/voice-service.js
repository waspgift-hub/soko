// Server-side ElevenLabs text-to-speech for AI replies.
//
// ── Why this file exists and where the secret lives ──
//
// The ElevenLabs API key is read from the environment HERE and never leaves the
// server. There is no code path that returns it, echoes it, or accepts it from a
// client: the request the app makes is `POST /api/ai/messages/:id/voice` with its
// Firebase token and nothing else. A key embedded in the Flutter binary would be
// extractable by anyone with the APK, and the AI key is held to the same standard
// by the existing providers (groq-provider.js reads GROQ_API_KEY the same way).
//
// ── Why audio is cached ──
//
// Every ElevenLabs synthesis costs money and generates real text, so a user who
// replays an answer would otherwise re-pay for identical audio. The cache key is a
// hash of (messageId, voiceId, voice settings, model), which is stable across
// server restarts and across devices — so Test 6 played on a second phone costs
// nothing.
//
// The cache is Redis with an in-process LRU in front, for the same reason the rest
// of the server uses Redis: audio is transient and TTL-shaped, not durable media,
// so R2 would be the wrong tier. The in-process LRU absorbs the replay-within-one-
// session case, which is the common one, without a network hop; Redis is what makes
// the cache survive a restart and work across the two Render instances.
//
// It degrades to no cache rather than to an error: with Redis down, audio still
// synthesizes, it just costs a credit per play.
//
// ── Why a TTS failure is never a chat failure ──
//
// `generateSpeech` returns `{ ok: false }` instead of throwing. §13 is explicit: the
// text response must still reach the user and the UI must show "Voice unavailable.
// Tap to retry." Turning a vendor outage into a failed chat would be a strictly
// worse product than a missing voice button.

const crypto = require('crypto');
const { getRedis, redisReady } = require('../../../config/redis');

const ELEVENLABS_TTS_URL = 'https://api.elevenlabs.io/v1/text-to-speech';

// Non-configured is the common case in development and in CI, and it must be
// cheap and loud rather than expensive and slow.
const SYNTHESIS_TIMEOUT_MS = 20_000;

// Output is capped because the response is held in memory and cached. A
// pathological assistant message (a 4,000-word essay) would otherwise be a very
// large base64 blob in Redis; 900 KB of mp3 is still roughly six minutes of speech.
const MAX_AUDIO_BYTES = 900 * 1024;

// Replay is the overwhelmingly common access pattern, so a small LRU in front of
// Redis removes the round trip for the same user in the same session.
const LRU_MAX_ENTRIES = 48;
const LRU_MAX_BYTES = 24 * 1024 * 1024;

// How long a cached clip lives. Long enough that a user coming back to a thread
// next week still gets free audio; short enough that regenerating after a voice
// model update is not a permanent loss.
const CACHE_TTL_SECONDS = 60 * 60 * 24 * 7;

const lru = new Map();
let lruBytes = 0;

function isConfigured() {
  return Boolean(process.env.ELEVENLABS_API_KEY);
}

/**
 * The single cache key for one synthesis.
 *
 * Model and stability are included because changing either produces different audio
 * from identical text, and reusing the old clip would silently serve the wrong
 * voice. Everything is hashed so the key is fixed-length and safe to use as a Redis
 * key regardless of voice id length or punctuation.
 */
function cacheKey({ messageId, voiceId, settings = {} }) {
  const shape = JSON.stringify({
    v: 1,
    messageId: String(messageId),
    voiceId: String(voiceId),
    model: settings.model || 'eleven_multilingual_v2',
    stability: settings.stability ?? 0.5,
    similarity: settings.similarityBoost ?? 0.75,
    style: settings.style ?? 0,
    speed: settings.speed ?? 1,
  });
  return `aiv:${crypto.createHash('sha256').update(shape).digest('hex')}`;
}

function voiceId() {
  return process.env.ELEVENLABS_VOICE_ID || '21m00Tcm4TlvDq8ikWAM';
}

function lruGet(key) {
  const hit = lru.get(key);
  if (!hit) return null;
  // Refresh recency so a replay keeps an entry alive against the LRU bound.
  lru.delete(key);
  lru.set(key, hit);
  return hit;
}

function lruSet(key, entry) {
  lru.set(key, entry);
  lruBytes += entry.buffer.length;
  while (lruBytes > LRU_MAX_BYTES && lru.size > 1) {
    const oldest = lru.keys().next().value;
    const dropped = lru.get(oldest);
    lru.delete(oldest);
    lruBytes -= dropped.buffer.length;
  }
}

async function redisGet(key) {
  if (!redisReady()) return null;
  try {
    const encoded = await getRedis().get(key);
    return encoded ? Buffer.from(encoded, 'base64') : null;
  } catch (err) {
    // A cache miss caused by Redis being unreachable must be indistinguishable
    // from a genuine miss, so the read fails soft.
    console.warn(`[ai] voice cache read failed: ${err.message}`);
    return null;
  }
}

async function redisSet(key, buffer) {
  if (!redisReady()) return;
  try {
    await getRedis().set(key, buffer.toString('base64'), 'EX', CACHE_TTL_SECONDS);
  } catch (err) {
    console.warn(`[ai] voice cache write failed: ${err.message}`);
  }
}

/**
 * Produces mp3 audio for [text], reusing a cached clip when one exists.
 *
 * @param {object} args
 * @param {string} args.text the assistant reply to speak
 * @param {string} args.messageId stable id, part of the cache key
 * @param {string} [args.voiceId] overrides ELEVENLABS_VOICE_ID
 * @param {boolean} [args.force] bypass the cache (used by an explicit retry)
 * @returns {Promise<{ok: true, audio: Buffer, mimeType: string, cached: boolean, cacheKey: string}
 *   | {ok: false, reason: string}>} never throws
 */
async function generateSpeech({ text, messageId: id, voiceId: requestedVoiceId, force = false }) {
  const body = String(text || '').trim();
  if (!body) return { ok: false, reason: 'EMPTY_TEXT' };
  if (!isConfigured()) return { ok: false, reason: 'ELEVENLABS_NOT_CONFIGURED' };

  const speaker = requestedVoiceId || voiceId();
  const key = cacheKey({ messageId: id, voiceId: speaker, settings: {} });

  if (!force) {
    const local = lruGet(key);
    if (local) return { ok: true, audio: local.buffer, mimeType: 'audio/mpeg', cached: true, cacheKey: key };
    const shared = await redisGet(key);
    if (shared) {
      lruSet(key, { buffer: shared });
      return { ok: true, audio: shared, mimeType: 'audio/mpeg', cached: true, cacheKey: key };
    }
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), SYNTHESIS_TIMEOUT_MS);
  try {
    const response = await fetch(`${ELEVENLABS_TTS_URL}/${encodeURIComponent(speaker)}`, {
      method: 'POST',
      headers: {
        'xi-api-key': process.env.ELEVENLABS_API_KEY,
        'Content-Type': 'application/json',
        Accept: 'audio/mpeg',
      },
      body: JSON.stringify({
        text: body,
        model_id: process.env.ELEVENLABS_MODEL || 'eleven_multilingual_v2',
        voice_settings: {
          stability: voiceSetting('ELEVENLABS_STABILITY', 0.5),
          similarity_boost: voiceSetting('ELEVENLABS_SIMILARITY_BOOST', 0.75),
          style: voiceSetting('ELEVENLABS_STYLE', 0),
        },
      }),
      signal: controller.signal,
    });

    if (!response.ok) {
      const detail = await response.text().catch(() => '');
      console.warn(`[ai] elevenlabs ${response.status}: ${detail.slice(0, 200)}`);
      // 401 means the key is wrong, which every user would hit identically, so it
      // is worth a louder log than a per-request quota 429.
      if (response.status === 401) console.error('[ai] ELEVENLABS_API_KEY rejected — voice is disabled until it is fixed');
      return { ok: false, reason: `ELEVENLABS_${response.status}`, status: response.status };
    }

    const buffer = Buffer.from(await response.arrayBuffer());
    if (!buffer.length) return { ok: false, reason: 'ELEVENLABS_EMPTY_AUDIO' };
    if (buffer.length > MAX_AUDIO_BYTES) {
      console.warn(`[ai] elevenlabs returned ${buffer.length} bytes — not cached`);
      return { ok: true, audio: buffer, mimeType: 'audio/mpeg', cached: false, cacheKey: null };
    }

    lruSet(key, { buffer });
    await redisSet(key, buffer);
    return { ok: true, audio: buffer, mimeType: 'audio/mpeg', cached: false, cacheKey: key };
  } catch (err) {
    const timedOut = err.name === 'AbortError' || err.name === 'TimeoutError';
    console.warn(`[ai] elevenlabs ${timedOut ? 'timed out' : `failed: ${err.message}`}`);
    return { ok: false, reason: timedOut ? 'ELEVENLABS_TIMEOUT' : 'ELEVENLABS_NETWORK' };
  } finally {
    clearTimeout(timer);
  }
}

function voiceSetting(key, fallback) {
  const parsed = Number.parseFloat(process.env[key]);
  return Number.isFinite(parsed) ? parsed : fallback;
}

/** Cache state for boot logging and the health endpoint. */
function status() {
  return {
    configured: isConfigured(),
    voiceId: isConfigured() ? voiceId() : null,
    cacheEntries: lru.size,
    cacheBytes: lruBytes,
    redisShared: redisReady(),
  };
}

module.exports = {
  generateSpeech,
  cacheKey,
  status,
  isConfigured,
  CACHE_TTL_SECONDS,
  MAX_AUDIO_BYTES,
};