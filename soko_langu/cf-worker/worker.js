// Cloudflare Worker: Soko Vibe API edge cache + reverse proxy.
//
// Sits in front of the Render origin (soko-langu-server.onrender.com) and
// serves the hot read routes from the edge (200+ Cloudflare cities) so the
// origin (and its Firestore/Redis reads) only gets hit on a cache miss.
//
// Caching policy (all mutations + non-whitelisted paths proxy straight through):
//   GET  /api/trust/passport/:sellerId   -> cache 300s, keyed by path only
//                                           (response is seller-agnostic, so all
//                                           viewers share ONE edge entry)
//   GET  /api/transaction-status/:id     -> cache 15s, keyed by path + token hash
//   POST /api/search/global-search       -> cache 60s, keyed by path + body hash
//   POST /api/search/autocomplete        -> cache 90s, keyed by path + body hash
//   POST /api/search/trending            -> cache 300s, keyed by path + body hash
//   POST /api/search/most-rated          -> cache 600s, keyed by path + body hash
//   everything else                      -> passthrough (never cached)
//
// Stale-while-revalidate: an expired-but-present entry is served immediately
// and refreshed in the background, so a thundering herd never reaches Render.

const ORIGIN = (typeof ORIGIN_URL !== 'undefined' && ORIGIN_URL)
  ? ORIGIN_URL
  : 'https://soko-langu-server.onrender.com';

const CACHE_RULES = [
  { match: (m) => m.pathname.startsWith('/api/trust/passport/'), ttl: 300, keyAuth: false, keyBody: false },
  { match: (m) => m.pathname.startsWith('/api/transaction-status/'), ttl: 15, keyAuth: true, keyBody: false },
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
  if (rule.keyBody) {
    const body = await request.clone().text();
    return `${rule.ttl}:${meta.pathname}${searchText}#${await sha256(body)}`;
  }
  if (rule.keyAuth) {
    const auth = request.headers.get('Authorization') || '';
    return `${rule.ttl}:${meta.pathname}${searchText}#${await sha256(auth)}`;
  }
  return `${rule.ttl}:${meta.pathname}${searchText}`;
}

function isCached(method, pathname) {
  return CACHE_RULES.some((r) => r.match({ method, pathname }));
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const method = request.method;
    const pathname = url.pathname;
    const meta = { method, pathname };

    // Passthrough everything that isn't on the cache whitelist.
    const rule = CACHE_RULES.find((r) => r.match(meta));
    if (!rule) {
      return proxyToOrigin(request, url);
    }

    const cache = caches.default;
    const cacheKey = new Request(`${ORIGIN}${pathname}`, { method: method, headers: request.headers });
    const cacheKeyFinal = await buildCacheKey(request, meta, rule);
    const cacheUrl = new URL(`${ORIGIN}${cacheKeyFinal}`);
    const keyWithPath = new Request(cacheUrl, { method: method });

    const cachedRes = await cache.match(keyWithPath);
    if (cachedRes) {
      const fetchAt = Number(cachedRes.headers.get('x-edge-fetch-at') || 0);
      const ageMs = Date.now() - fetchAt;
      if (ageMs <= rule.ttl * 1000) {
        // Fresh hit — serve straight from the edge.
        return cloneResponse(cachedRes);
      }
      // Stale hit — serve immediately, revalidate in background.
      ctx.waitUntil(revalidateAndStore(cache, keyWithPath, request, url, rule, cacheKeyFinal));
      return cloneResponse(cachedRes);
    }

    // Cold miss — fetch from origin and store.
    const originRes = await proxyFetch(request, url);
    if (originRes.status === 200) {
      ctx.waitUntil(cache.put(keyWithPath, tagResponse(originRes.clone())));
    }
    return originRes;
  },
};

async function revalidateAndStore(cache, keyWithPath, request, url, rule, cacheKeyFinal) {
  try {
    const originRes = await proxyFetch(request, url);
    if (originRes.status === 200) {
      await cache.put(keyWithPath, tagResponse(originRes));
    }
  } catch (e) {
    // Keep serving stale; nothing more to do.
  }
}

async function proxyFetch(request, url) {
  const target = new URL(url.pathname + url.search, ORIGIN);
  const headers = new Headers(request.headers);
  headers.delete('host');
  headers.set('x-edge-colo', 'cf');
  // Tell origin this came via the edge so its own Redis cache layer still
  // applies but its general rate limiter stays fair (shared across clients).
  headers.set('x-forwarded-proto', 'https');
  headers.set('x-forwarded-host', url.hostname);
  const init = {
    method: request.method,
    headers,
    body: ['GET', 'HEAD'].includes(request.method) ? undefined : request.body,
    redirect: 'follow',
  };
  return fetch(target, init);
}

function proxyToOrigin(request, url) {
  return proxyFetch(request, url);
}

function tagResponse(res) {
  const headers = new Headers(res.headers);
  headers.set('x-edge-fetch-at', String(Date.now()));
  headers.set('x-soko-edge', '1');
  return new Response(res.body, { status: res.status, statusText: res.statusText, headers });
}

function cloneResponse(res) {
  // Fresh clones keep the edge stamp for metrics.
  return new Response(res.body, { status: res.status, statusText: res.statusText, headers: res.headers });
}