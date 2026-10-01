// YouTube Data API v3 search proxy.
//
// Why a proxy: the browser API key must never ship inside the app (quota
// theft + key abuse). The app calls /api/v1/youtube/search with its Firebase
// token; the server injects YOUTUBE_API_KEY, caches per normalized query
// (search.list costs 100 quota units — the cache IS the quota plan), and
// returns only id/title/channel/thumbnail. Playback itself uses the official
// nocookie embed player in-app, so no download/rip ever happens.
const SEARCH_URL = 'https://www.googleapis.com/youtube/v3/search';

const CACHE_TTL_MS = 60 * 60 * 1000;
const MAX_CACHE_ENTRIES = 200;

const searchCache = new Map();

function cacheGet(key) {
  const entry = searchCache.get(key);
  if (!entry) return undefined;
  if (entry.expiresAt <= Date.now()) {
    searchCache.delete(key);
    return undefined;
  }
  return entry.value;
}

function cacheSet(key, value) {
  if (searchCache.size >= MAX_CACHE_ENTRIES) {
    const oldest = searchCache.keys().next().value;
    searchCache.delete(oldest);
  }
  searchCache.set(key, { value, expiresAt: Date.now() + CACHE_TTL_MS });
}

function httpError(status, message) {
  const err = new Error(message);
  err.status = status;
  return err;
}

// Pure shape parser — unit-tested, no network.
function parseYouTubeSearch(body) {
  const items = Array.isArray(body && body.items) ? body.items : [];
  return items
    .filter((it) => it && it.id && it.id.videoId && it.snippet)
    .map((it) => ({
      videoId: String(it.id.videoId),
      title: String(it.snippet.title || ''),
      channel: String(it.snippet.channelTitle || ''),
      thumbnail: String(
        (it.snippet.thumbnails &&
          (it.snippet.thumbnails.medium || {}).url) ||
          (it.snippet.thumbnails && (it.snippet.thumbnails.default || {}).url) ||
          '',
      ),
      publishedAt: String(it.snippet.publishedAt || ''),
    }));
}

async function searchYouTube({ q, maxResults = 10, fetchImpl = fetch }) {
  const key = process.env.YOUTUBE_API_KEY;
  if (!key) throw httpError(503, 'YOUTUBE_NOT_CONFIGURED');

  const query = String(q || '').trim();
  if (query.length < 2 || query.length > 100) {
    throw httpError(400, 'QUERY_TOO_SHORT');
  }
  const take = Math.min(25, Math.max(1, Number(maxResults) || 10));

  const cacheKey = `${query.toLowerCase()}|${take}`;
  const hit = cacheGet(cacheKey);
  if (hit) return { ...hit, cached: true };

  const url = new URL(SEARCH_URL);
  url.searchParams.set('part', 'snippet');
  url.searchParams.set('type', 'video');
  url.searchParams.set('videoEmbeddable', 'true');
  url.searchParams.set('maxResults', String(take));
  url.searchParams.set('q', query);
  url.searchParams.set('key', key);

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 10000);
  let res;
  try {
    res = await fetchImpl(url.toString(), { signal: controller.signal });
  } catch (e) {
    throw httpError(502, 'YOUTUBE_UPSTREAM_UNREACHABLE');
  } finally {
    clearTimeout(timer);
  }
  if (!res.ok) throw httpError(502, `YOUTUBE_UPSTREAM_${res.status}`);
  const body = await res.json();
  const data = { success: true, items: parseYouTubeSearch(body) };
  cacheSet(cacheKey, data);
  return { ...data, cached: false };
}

module.exports = { searchYouTube, parseYouTubeSearch };
