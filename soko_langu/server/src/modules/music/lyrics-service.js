// Synced song lyrics: public LRC lookup with an AI fallback.
//
// Why a server proxy: the app must not talk to the lyrics provider directly.
// Same reasoning as the YouTube key - a provider credential (or an unauthenticated
// client hitting a rate-limited public API from thousands of phones) belongs
// behind the server, where it can be cached, rate-limited and shaped.
//
// Why the AI fallback exists: a real synced-lyrics database covers a fraction of
// the songs on a user's phone. Without a fallback those songs just show nothing,
// and "no lyrics" is indistinguishable from "the app is broken". The AI writes
// lyrics in LRC form with timestamps spread over the track's real duration, so
// the synced viewer still works - the words are a guess, the timing is honest.
const aiGateway = require('../ai/ai-gateway');

const SEARCH_URL = 'https://lrclib.net/api/search';
const CACHE_TTL_MS = 24 * 60 * 60 * 1000;
const MAX_CACHE_ENTRIES = 500;
const UPSTREAM_TIMEOUT_MS = 8000;

// lrclib asks API clients to identify themselves; unidentified traffic is
// rate-limited harder and eventually blocked outright.
const UPSTREAM_HEADERS = { 'User-Agent': 'SokoVibe/1.0 (+https://sokovibe.co.tz)' };

const lyricsCache = new Map();

function cacheGet(key) {
  const entry = lyricsCache.get(key);
  if (!entry) return undefined;
  if (entry.expiresAt <= Date.now()) {
    lyricsCache.delete(key);
    return undefined;
  }
  return entry.value;
}

function cacheSet(key, value) {
  if (lyricsCache.size >= MAX_CACHE_ENTRIES) {
    const oldest = lyricsCache.keys().next().value;
    lyricsCache.delete(oldest);
  }
  lyricsCache.set(key, { value, expiresAt: Date.now() + CACHE_TTL_MS });
}

function httpError(status, message) {
  const err = new Error(message);
  err.status = status;
  return err;
}

function normalize(value) {
  return String(value == null ? '' : value)
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .trim();
}

// How far a candidate's length may differ from the user's file and still be
// considered the same recording. 8s covers provider metadata drift without
// letting a live version (typically minutes longer) pass for the studio cut.
const DURATION_TOLERANCE_SEC = 8;

/**
 * Picks the best candidate for the song the user actually has.
 *
 * The provider returns near-duplicates (live version, remix, remaster, a cover)
 * in no particular order. Duration is the strongest signal, because it is read
 * from the file itself rather than from the same metadata being matched
 * against.
 *
 * When the duration is known and nothing is close enough, this returns null on
 * purpose. A karaoke cover that happens to share the title would otherwise be
 * returned: the words would be wrong AND the highlight would drift, because
 * plain lyrics are re-timed to the wrong length. Returning null lets the caller
 * fall through to generated lyrics, which are at least the right length.
 */
function pickBest(candidates, { durationMs } = {}) {
  const usable = (Array.isArray(candidates) ? candidates : []).filter(
    (c) => c && (c.syncedLyrics || c.plainLyrics),
  );
  if (!usable.length) return null;

  if (Number.isFinite(durationMs) && durationMs > 0) {
    const target = durationMs / 1000;
    // Only candidates that actually declare a length can be judged on length.
    // The provider omits `duration` on some rows, and judging those by absence
    // would reject a correct match for a missing field.
    const timed = usable.filter((c) => Number.isFinite(c.duration));
    if (timed.length) {
      const near = timed.filter(
        (c) => Math.abs(c.duration - target) <= DURATION_TOLERANCE_SEC,
      );
      if (near.length) {
        const synced = near.find((c) => c.syncedLyrics);
        return synced || near[0];
      }
      // Every candidate declares a length and none is close: the database has
      // this title but not this recording. Let the caller fall back rather than
      // show the wrong words against the wrong timeline.
      return null;
    }
  }

  const synced = usable.find((c) => c.syncedLyrics);
  return synced || usable[0];
}

/**
 * Converts plain (unsynced) lyrics into timestamped LRC by spreading the lines
 * evenly across the track.
 *
 * The result is approximate and is returned as such: the client highlights in
 * step with playback, which is strictly better than a wall of text with no
 * position at all, and the client labels it as unsynced.
 */
function plainToLrc(plain, durationMs) {
  const lines = String(plain || '')
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter(Boolean);
  if (!lines.length) return '';
  const seconds = Number.isFinite(durationMs) && durationMs > 0 ? durationMs / 1000 : 180;
  const step = seconds / lines.length;
  const stamp = (s) => {
    const m = Math.floor(s / 60);
    const sec = Math.floor(s % 60);
    const cs = Math.floor((s % 1) * 100);
    return `[${String(m).padStart(2, '0')}:${String(sec).padStart(2, '0')}.${String(cs).padStart(2, '0')}]`;
  };
  return lines.map((line, i) => `${stamp(i * step)}${line}`).join('\n');
}

async function fetchCandidates({ title, artist }) {
  const params = new URLSearchParams({ track_name: title });
  if (artist) params.set('artist_name', artist);
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), UPSTREAM_TIMEOUT_MS);
  try {
    const res = await fetch(`${SEARCH_URL}?${params.toString()}`, {
      headers: UPSTREAM_HEADERS,
      signal: controller.signal,
    });
    if (!res.ok) return [];
    const body = await res.json();
    return Array.isArray(body) ? body : [];
  } catch (e) {
    // A provider outage must not fail the request: the AI fallback below still
    // produces something usable.
    console.warn(`[lyrics] provider lookup failed: ${e.message}`);
    return [];
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Asks the AI for lyrics already in LRC form.
 *
 * The prompt insists on LRC timestamps because the client has no way to add
 * them later - it does not know how the song is structured, only how long it is.
 */
async function generateWithAi({ title, artist, album, durationMs }) {
  const seconds = Number.isFinite(durationMs) && durationMs > 0 ? Math.round(durationMs / 1000) : 180;
  const prompt = [
    'Write song lyrics in LRC format.',
    `Title: ${title}${artist ? ` — ${artist}` : ''}${album ? ` (album: ${album})` : ''}`,
    `The track runs ${seconds} seconds.`,
    'Rules:',
    '- One line per lyric, each prefixed with an LRC timestamp like [01:23.45].',
    '- Start near [00:05.00] and space lines out across the full duration, ending near the end.',
    '- No blank lines, no headings, no artist credits, no explanation.',
    '- Output only the LRC lines.',
  ].join('\n');

  const { text, provider } = await aiGateway.chat({
    messages: [{ role: 'user', content: prompt }],
    max_tokens: 900,
    temperature: 0.7,
  });

  // Providers sometimes wrap the answer in a ```lrc fence or add a sentence of
  // preamble. Keep only the timestamped lines, so the client parser never has to
  // deal with prose.
  const lines = String(text || '')
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => /^\[\d{1,2}:\d{2}([.:]\d{1,3})?\]/.test(l));
  if (!lines.length) throw new Error('LYRICS_AI_NO_LRC');

  return { lrc: lines.join('\n'), provider };
}

/**
 * Resolves lyrics for one song.
 *
 * Order matters: a real synced LRC always beats AI output, even a badly matched
 * one, because it contains the true words. `source` is returned so the client
 * can tell the user which they are looking at.
 */
async function getLyrics({ title, artist, album, durationMs, allowAi = true }) {
  const cleanTitle = String(title || '').trim();
  if (!cleanTitle) throw httpError(400, 'LYRICS_TITLE_REQUIRED');
  if (cleanTitle.length > 200 || String(artist || '').length > 200) {
    throw httpError(400, 'LYRICS_TITLE_TOO_LONG');
  }

  const key = `${normalize(cleanTitle)}|${normalize(artist)}|${Number(durationMs) || 0}`;
  const cached = cacheGet(key);
  if (cached) return cached;

  const candidates = await fetchCandidates({ title: cleanTitle, artist });
  const best = pickBest(candidates, { durationMs });

  if (best && best.syncedLyrics) {
    const result = {
      lrc: best.syncedLyrics,
      source: 'synced',
      provider: 'lrclib',
      artist: best.artistName || artist || null,
      title: best.trackName || cleanTitle,
    };
    cacheSet(key, result);
    return result;
  }

  if (best && best.plainLyrics) {
    const result = {
      lrc: plainToLrc(best.plainLyrics, durationMs),
      source: 'estimated',
      provider: 'lrclib',
      artist: best.artistName || artist || null,
      title: best.trackName || cleanTitle,
    };
    cacheSet(key, result);
    return result;
  }

  if (!allowAi) {
    throw httpError(404, 'LYRICS_NOT_FOUND');
  }

  // Nothing in the database. Generate rather than return nothing, and say so.
  const { lrc, provider } = await generateWithAi({
    title: cleanTitle,
    artist,
    album,
    durationMs,
  });
  const result = { lrc, source: 'ai', provider: provider || null };
  cacheSet(key, result);
  return result;
}

module.exports = {
  getLyrics,
  // Exported for unit tests: pure, no network.
  pickBest,
  plainToLrc,
  normalize,
};