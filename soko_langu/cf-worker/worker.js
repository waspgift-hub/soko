// Cloudflare Worker: Soko Vibe API edge cache + reverse proxy.
//
// Sits in front of the Render origin(s) and serves the hot read routes from
// the edge (200+ Cloudflare cities) so the origin (and its Firestore/Redis
// reads) only gets hit on a cache miss.
//
// Regional routing: when REGION_ORIGIN_* vars are set, public catalog + search
// reads are proxied to the nearest regional Render replica (per Cloudflare
// continent). Personalised/auth paths always stay on the primary ORIGIN so
// stateful writes and redirects are never split across regions.
//
// Caching policy (all mutations + non-whitelisted paths proxy straight through):
//   GET  /api/trust/passport/:sellerId        -> cache 300s, keyed by path only
//   GET  /api/v1/trust/sellers/:id/passport    -> cache 300s, keyed by path only
//   GET  /api/transaction-status/:id           -> cache 15s, keyed by path + token hash
//   GET  /api/v1/products/categories           -> cache 3600s, keyed by path only
//   GET  /api/v1/products?...                  -> cache 30s, keyed by path+query only
//   GET  /api/v1/products/:idOrSlug            -> cache 30s, keyed by path only
//   POST /api/search/global-search             -> cache 60s, keyed by path + body hash
//   POST /api/search/autocomplete              -> cache 90s, keyed by path + body hash
//   POST /api/search/trending                  -> cache 300s, keyed by path + body hash
//   POST /api/search/most-rated                -> cache 600s, keyed by path + body hash
//   everything else                            -> passthrough (never cached)
//
// Stale-while-revalidate: an expired-but-present entry is served immediately
// and refreshed in the background, so a thundering herd never reaches Render.

// Workers run in modules format: `[vars]` and secrets arrive on `env`, NOT as
// globals. Resolve every origin from `env` first so wrangler.toml overrides
// (and regional replicas) actually take effect; the hardcoded URL is only the
// last-resort fallback.
const ORIGIN_FALLBACK = 'https://soko-langu-server.onrender.com';

function primaryOrigin(env) {
  return (env && env.ORIGIN_URL) || ORIGIN_FALLBACK;
}

// Regional origins (optional, for the 10M multi-region tier). Keys are
// Cloudflare continent codes; each maps to a regional Render replica. Leave a
// key empty and that continent falls back to the primary ORIGIN. Add matching
// env vars (`REGION_ORIGIN_*`) in wrangler.toml [vars] when replicas exist.
function regionalOrigins(env) {
  return {
    /* e.g. AF: 'https://soko-africa.onrender.com' */
    AF: (env && env.REGION_ORIGIN_AF) || '',
    EU: (env && env.REGION_ORIGIN_EU) || '',
    AS: (env && env.REGION_ORIGIN_AS) || '',
    NA: (env && env.REGION_ORIGIN_NA) || '',
  };
}

// Only meaningful for region-agnostic (public catalog) reads; personalised
// paths (auth, payments) MUST stay on the primary so regional replicas can
// never serve a redirect/consistency mismatch. This is enforced in resolveOrigin.
const REGION_ROUTABLE = (m) =>
  (m.method === 'GET' && m.pathname.startsWith('/api/v1/products')) ||
  (m.method === 'POST' && m.pathname === '/api/search/trending') ||
  (m.method === 'POST' && m.pathname === '/api/search/most-rated');

function resolveOrigin(request, env, meta) {
  const continent = request.cf?.continent || '';
  if (REGION_ROUTABLE(meta)) {
    const regional = regionalOrigins(env)[continent];
    if (regional) return regional;
  }
  return primaryOrigin(env);
}

// All cache rules evaluated top-to-bottom; first match wins.
const CACHE_RULES = [
  // --- Trust passport (v2 + legacy paths) ---
  { match: (m) => m.pathname.startsWith('/api/trust/passport/'), ttl: 300, keyAuth: false, keyBody: false },
  { match: (m) => m.pathname.startsWith('/api/v1/trust/sellers/') && m.pathname.endsWith('/passport'), ttl: 300, keyAuth: false, keyBody: false },

  // --- Transaction status (personalised, short TTL) ---
  { match: (m) => m.pathname.startsWith('/api/transaction-status/'), ttl: 15, keyAuth: true, keyBody: false },

  // --- Catalog: categories rarely change ---
  { match: (m) => m.method === 'GET' && m.pathname === '/api/v1/products/categories', ttl: 3600, keyAuth: false, keyBody: false },

  // --- Catalog: product list (public browse, varies by query string) ---
  { match: (m) => m.method === 'GET' && m.pathname === '/api/v1/products', ttl: 30, keyAuth: false, keyBody: false },

  // --- Catalog: product detail (very hot, varies by id/slug) ---
  { match: (m) => m.method === 'GET' && m.pathname.startsWith('/api/v1/products/') && !m.pathname.includes('/categories'), ttl: 30, keyAuth: false, keyBody: false },

  // --- Search endpoints (POST, keyed by body) ---
  { match: (m) => m.method === 'POST' && m.pathname === '/api/search/autocomplete', ttl: 90, keyAuth: false, keyBody: true },
  { match: (m) => m.method === 'POST' && m.pathname === '/api/search/trending', ttl: 300, keyAuth: false, keyBody: true },
  { match: (m) => m.method === 'POST' && m.pathname === '/api/search/most-rated', ttl: 600, keyAuth: false, keyBody: true },
  { match: (m) => m.method === 'POST' && m.pathname === '/api/search/global-search', ttl: 60, keyAuth: false, keyBody: true },
];

async function sha256(text) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

async function buildCacheKey(request, meta, rule) {
  const url = new URL(request.url);
  const searchText = url.search.length > 0 ? '?' + url.search : '';
  // Method is part of the key so a GET and a POST rule that ever land on the
  // same path cannot share an entry.
  const prefix = `${rule.ttl}:${meta.method}`;
  if (rule.keyBody) {
    const body = await request.clone().text();
    return `${prefix}:${meta.pathname}${searchText}#${await sha256(body)}`;
  }
  if (rule.keyAuth) {
    const auth = request.headers.get('Authorization') || '';
    return `${prefix}:${meta.pathname}${searchText}#${await sha256(auth)}`;
  }
  return `${prefix}:${meta.pathname}${searchText}`;
}

// Scanner/probe paths that never exist on this API. Answered at the edge so
// botnets and vulnerability scanners never spend origin (Render) CPU, Firestore
// reads, or rate-limit budget.
const PROBE_PATTERNS = [
  /^\/\.env(\.|$|\/)/,
  /^\/\.git(\/|$)/,
  /^\/\.well-known\/(?!assetlinks\.json|apple-app-site-association)/,
  /^\/wp-(admin|login|content|includes)/,
  /\/phpmyadmin/i,
  /\.php($|\?)/,
  /^\/server-status/,
  /^\/actuator(\/|$)/,
  /^\/\.DS_Store$/,
  /^\/.(aws|ssh|docker)/,
];

function isProbe(pathname) {
  return PROBE_PATTERNS.some((re) => re.test(pathname));
}

// Mirrors the origin's 1mb JSON body cap: oversized payloads are rejected at
// the edge instead of being proxied to Render just to be re-rejected there.
const MAX_BODY_BYTES = 1024 * 1024;

// Coarse abuse brake for uncached (mutation/auth) traffic when a KV namespace
// is bound as RATE_LIMIT_KV. KV is eventually consistent, so this is a
// dampener, not a precise gate — the origin's Redis/memory limiters stay the
// source of truth. Unset binding = skip silently (zero behaviour change).
const EDGE_RATE_LIMIT_PER_MIN = 120;

async function edgeRateLimit(request, env, ctx) {
  const kv = env && env.RATE_LIMIT_KV;
  if (!kv) return null;
  const ip = request.headers.get('cf-connecting-ip') || 'unknown';
  const window = Math.floor(Date.now() / 60000);
  const key = `edge-rl:${ip}:${window}`;
  let count = 0;
  try {
    count = Number(await kv.get(key)) || 0;
  } catch (e) {
    return null;
  }
  if (count >= EDGE_RATE_LIMIT_PER_MIN) {
    return new Response(JSON.stringify({ success: false, error: 'Too many requests' }), {
      status: 429,
      headers: { 'content-type': 'application/json', 'retry-after': '60' },
    });
  }
  ctx.waitUntil(kv.put(key, String(count + 1), { expirationTtl: 120 }).catch(() => {}));
  return null;
}

// Security headers applied to every response the edge returns. The origin sets
// its own CSP for HTML pages; the edge layer only adds transport/embedding
// guards that are safe for both JSON and HTML.
function withSecurityHeaders(res, edgeCache) {
  const headers = new Headers(res.headers);
  headers.set('strict-transport-security', 'max-age=31536000; includeSubDomains');
  headers.set('x-content-type-options', 'nosniff');
  headers.set('referrer-policy', 'strict-origin-when-cross-origin');
  headers.set('permissions-policy', 'camera=(), microphone=(), geolocation=()');
  headers.delete('x-powered-by');
  headers.delete('server');
  if (edgeCache) headers.set('x-edge-cache', edgeCache);
  return new Response(res.body, { status: res.status, statusText: res.statusText, headers });
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const method = request.method;
    const pathname = url.pathname;
    const meta = { method, pathname };
    const origin = resolveOrigin(request, env, meta);

    // 1. Drop scanner probes before they cost anything downstream.
    if (isProbe(pathname)) {
      return withSecurityHeaders(
        new Response(JSON.stringify({ success: false, error: 'Not found' }), {
          status: 404,
          headers: { 'content-type': 'application/json' },
        }),
      );
    }

    // 2. Reject oversized request bodies at the edge (origin caps at 1mb).
    if (method !== 'GET' && method !== 'HEAD') {
      const declared = Number(request.headers.get('content-length') || 0);
      if (declared > MAX_BODY_BYTES) {
        return withSecurityHeaders(
          new Response(JSON.stringify({ success: false, error: 'Payload too large' }), {
            status: 413,
            headers: { 'content-type': 'application/json' },
          }),
        );
      }
    }

    // 3. Coarse per-IP brake on uncached traffic (KV-bound only). Cached
    // reads are already absorbed by the edge cache, so they skip the check.
    const rule = CACHE_RULES.find((r) => r.match(meta));
    if (!rule) {
      const limited = await edgeRateLimit(request, env, ctx);
      if (limited) return withSecurityHeaders(limited);
      return withSecurityHeaders(await proxyToOrigin(request, url, origin, env));
    }

    // 4. Cached flow with stale-while-revalidate.
    //
    // A cache bug must never be able to take the API offline, so every failure
    // below degrades to a plain proxied response instead of throwing.
    const cache = caches.default;
    const cacheKeyFinal = await buildCacheKey(request, meta, rule);

    // Synthetic, stable cache-key URL. Two hard requirements:
    //  1. It MUST be a GET Request. Cloudflare's Cache API only matches and
    //     stores GET: `cache.match()` on a POST Request misses every time and
    //     `cache.put()` rejects it. The original code used `{ method: method }`,
    //     so all four POST search routes were never cached — every app open hit
    //     Render and tripped `searchLimiter` (30/min) into 429s, emptying the
    //     trending / most-rated carousels.
    //  2. The key MUST be encoded into the PATH, never concatenated onto the
    //     origin. `new URL(origin + ttl + pathname)` built a malformed authority
    //     (`…onrender.com3600:/api/…`); folding the method in turned the second
    //     colon into a non-numeric port, `new URL()` threw, and every request
    //     through the edge returned 500.
    // `.invalid` is reserved by RFC 2606 and can never resolve — fine, because
    // this URL is only ever a cache key and is never fetched.
    let keyWithPath;
    try {
      // The resolved origin is folded into the key so the same path served from
      // different regions never shares an entry with a foreign origin.
      const cacheUrl = new URL('https://soko-edge-cache.invalid/k/');
      cacheUrl.pathname = `/k/${encodeURIComponent(`${origin}|${cacheKeyFinal}`)}`;
      keyWithPath = new Request(cacheUrl, { method: 'GET' });
    } catch (e) {
      return withSecurityHeaders(
        await proxyFetch(request, url, origin, env),
        'MISS-NOKEY',
      );
    }

    const cachedRes = await cache.match(keyWithPath);
    if (cachedRes) {
      const fetchAt = Number(cachedRes.headers.get('x-edge-fetch-at') || 0);
      const ageMs = Date.now() - fetchAt;
      if (ageMs <= rule.ttl * 1000) {
        // Fresh hit — serve straight from the edge.
        return withSecurityHeaders(cloneResponse(cachedRes, 'HIT'));
      }
      // Stale hit — serve immediately, revalidate in background.
      ctx.waitUntil(revalidateAndStore(cache, keyWithPath, request, url, rule, origin, env));
      return withSecurityHeaders(cloneResponse(cachedRes, 'STALE'));
    }

    // Cold miss — fetch from origin and store.
    const originRes = await proxyFetch(request, url, origin, env);
    if (originRes.status !== 200) {
      // Never cache an error. A stored 429 would keep serving RATE_LIMITED to
      // every user for the whole TTL, turning a transient origin blip into an
      // outage that lasts far longer than the blip.
      return withSecurityHeaders(originRes, 'MISS-ORIGIN-ERROR');
    }
    // A failed store must not surface as an unhandled rejection: the response
    // is already correct, only the next request pays origin cost again.
    ctx.waitUntil(cache.put(keyWithPath, tagResponse(originRes.clone())).catch(() => {}));
    return withSecurityHeaders(originRes, 'MISS');
  },
};

async function revalidateAndStore(cache, keyWithPath, request, url, rule, origin, env) {
  try {
    const originRes = await proxyFetch(request, url, origin, env);
    if (originRes.status === 200) {
      await cache.put(keyWithPath, tagResponse(originRes));
    }
  } catch (e) {
    // Keep serving stale; nothing more to do.
  }
}

async function proxyFetch(request, url, origin, env) {
  const fallback = (env && env.ORIGIN_URL) || ORIGIN_FALLBACK;
  const target = new URL(url.pathname + url.search, origin || fallback);
  const headers = new Headers(request.headers);
  headers.delete('host');
  headers.set('x-edge-colo', 'cf');
  // Tell origin this came via the edge so its own Redis cache layer still
  // applies but its general rate limiter stays fair (shared across clients).
  headers.set('x-forwarded-proto', 'https');
  headers.set('x-forwarded-host', url.hostname);
  headers.set('x-soko-origin', origin || fallback);
  // Shared edge secret (wrangler secret EDGE_SECRET, mirrored on Render).
  // Lets the origin trust cf-connecting-ip for rate-limit keys; absent secret
  // = origin keeps keying on the socket IP exactly as before.
  if (env && env.EDGE_SECRET) headers.set('x-soko-edge', env.EDGE_SECRET);
  const init = {
    method: request.method,
    headers,
    body: ['GET', 'HEAD'].includes(request.method) ? undefined : request.body,
    redirect: 'follow',
    // Never let a hung origin hold an edge request longer than the origin's
    // own 20s request timeout.
    signal: AbortSignal.timeout(25000),
  };
  return fetch(target, init);
}

function proxyToOrigin(request, url, origin, env) {
  return proxyFetch(request, url, origin, env);
}

function tagResponse(res) {
  const headers = new Headers(res.headers);
  headers.set('x-edge-fetch-at', String(Date.now()));
  headers.set('x-soko-edge', '1');
  return new Response(res.body, { status: res.status, statusText: res.statusText, headers });
}

function cloneResponse(res, edgeCache) {
  // Fresh clones keep the edge stamp for metrics.
  const headers = new Headers(res.headers);
  headers.set('x-edge-cache', edgeCache || 'HIT');
  return new Response(res.body, { status: res.status, statusText: res.statusText, headers });
}