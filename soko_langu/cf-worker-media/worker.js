/**
 * soko-media — R2 media edge for sokovibe.co.tz
 *
 * ONE hostname (`media.sokovibe.co.tz`) fronts all four R2 buckets. A single
 * bucket custom domain cannot do this, and per-kind subdomains would fragment
 * the cache and leak the storage layout. Object keys already start with the
 * logical kind (`images/…`, `videos/…`, `thumbnails/…` — see
 * server/src/modules/media/upload-service.js), so the first path segment is the
 * bucket selector and no request ever names a bucket directly.
 *
 * Why this exists: before it, every product photo and avatar upload went to
 * Cloudinary (3rd party, egress billed, no range support). R2 was provisioned
 * with working credentials but had no public surface at all — no bucket custom
 * domain and no DNS record — so R2 URLs 404'd.
 *
 * Caching: object keys embed a UUID (`…/<ownerId>/<uuid>.<ext>`) and uploads
 * never overwrite an existing key, so every object is immutable. That lets us
 * serve `immutable, max-age=1y` and lets the Cache API hold full responses so
 * repeat views stop billing R2 class-B reads.
 */

// key prefix -> R2 binding
const BUCKET_FOR_PREFIX = [
  { prefix: 'images', binding: 'IMAGES' },
  { prefix: 'videos', binding: 'VIDEOS' },
  { prefix: 'thumbnails', binding: 'THUMBNASTS' },
  { prefix: 'backups', binding: 'BACKUPS' },
  // Application artwork (category/subcategory photos the app downloads as an
  // optional post-install pack). Public application data, not user uploads, so
  // it lives in its own bucket rather than under `images/` where the
  // `<kind>s/<ownerType>/<ownerId>/<uuid>` key convention applies. Key layout is
  // `artwork/<version>/<relative path>`, and the app only ever reads paths
  // listed in the pack's own manifest.
  { prefix: 'artwork', binding: 'ARTWORK' },
];

// KYC identity documents (passport/ID, selfie) must never be reachable through
// this Worker. Two independent reasons, and both must hold:
//
//  1. There is NO `kyc` binding below. Even a routing bug on this file cannot
//     read the private bucket, because the binding does not exist in this
//     deployment at all.
//  2. The prefix is still refused explicitly below rather than falling through to
//     the "unknown namespace" 404, so the refusal is intentional and greppable
//     instead of an accident of the bucket map.
//
// The only supported read path is a short-lived presigned GET minted by the API
// after it authorises the caller (`GET /api/v1/kyc/documents/:id/read-url` for
// the owner, `GET /api/v1/admin/kyc/:userId/:id/read-url` for a reviewer). Those
// URLs point at R2 directly and do not traverse this Worker.
const DENIED_PREFIXES = ['kyc'];

const IMMUTABLE = 'public, max-age=31536000, immutable';
const ONE_HOUR = 'public, max-age=3600';
// Artwork manifests are small and change only on a pack release, but they MUST
// stay revalidatable or a shipped app could never learn about an update.
const MANIFEST = 'public, max-age=300, must-revalidate';

function bindingFor(key) {
  const seg = key.split('/')[0];
  if (DENIED_PREFIXES.includes(seg)) return { denied: true };
  const hit = BUCKET_FOR_PREFIX.find((b) => b.prefix === seg);
  return hit ? { binding: hit.binding } : { unknown: true };
}

function isDeniedPrefix(key) {
  return DENIED_PREFIXES.includes(key.split('/')[0]);
}

/**
 * True when the client's If-None-Match list contains the current ETag.
 *
 * Compares on the quoted hash only, ignoring the `W/` weak prefix, and treats
 * `*` as a match per RFC 9110.
 */
function etagMatches(ifNoneMatch, etag) {
  if (!ifNoneMatch || !etag) return false;
  const normalise = (v) => v.trim().replace(/^W\//, '');
  const current = normalise(etag);
  return ifNoneMatch
    .split(',')
    .map(normalise)
    .some((candidate) => candidate === '*' || candidate === current);
}

/**
 * Cache-Control for a key.
 *
 * `artwork/manifest.json` is the one object that must stay revalidatable: it is
 * how a shipped app learns a newer pack exists, so an immutable header on it
 * would strand users on an old pack indefinitely. Everything else is keyed by
 * content/version and is genuinely immutable.
 */
function cacheControlFor(key) {
  if (key.endsWith('manifest.json')) return MANIFEST;
  if (key.startsWith('videos/')) return ONE_HOUR;
  return IMMUTABLE;
}

function errorResponse(status, message, extraHeaders) {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Cache-Control': 'no-store',
      ...(extraHeaders || {}),
    },
  });
}

export default {
  async fetch(request, env, ctx) {
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      // Public media bucket: refuse writes/anything else outright. There is no
      // upload path through here — clients PUT to presigned S3 URLs.
      return errorResponse(405, 'method_not_allowed');
    }

    const url = new URL(request.url);
    const key = decodeURIComponent(url.pathname.replace(/^\/+/, ''));
    if (!key) return errorResponse(400, 'missing_key');

    const target = bindingFor(key);
    if (target.denied) {
      return errorResponse(403, 'private_media_namespace', { 'x-media-denied': 'kyc' });
    }
    if (target.unknown) return errorResponse(404, 'unknown_media_namespace');

    const bucket = env[target.binding];
    if (!bucket) return errorResponse(500, 'bucket_unavailable');

    // Range support: Flutter's video player and Safari both request byte
    // ranges. Passing the incoming Range header straight to R2 is what makes
    // seeking work instead of forcing a full 500MB download.
    const range = request.headers.get('range');
    const isPartial = Boolean(range);

    // Only full GETs go in the Cache API — a 206 cannot be cached as a whole
    // object and would poison later full requests for the same key.
    const cacheKeyUrl = new URL(request.url);
    cacheKeyUrl.search = '';
    const cacheKey = new Request(cacheKeyUrl.toString(), { method: 'GET' });
    const cache = caches.default;

    const inm = request.headers.get('if-none-match');

    // A conditional request bypasses the Cache API entirely. Reading the
    // object and comparing ETags ourselves is deterministic, whereas letting a
    // cached response answer the conditional depends on the cached copy
    // carrying a readable validator — and when it does not, the client silently
    // re-downloads the body on every poll.
    if (!isPartial && request.method === 'GET' && !inm) {
      const cached = await cache.match(cacheKey);
      if (cached) return cached;
    }

    let object;
    try {
      object = isPartial
        ? await bucket.get(key, { range: request.headers })
        : await bucket.get(key);
    } catch {
      return errorResponse(500, 'media_read_failed');
    }

    if (!object) return errorResponse(404, 'media_not_found');

    // Answer the conditional here, before any body is read into a Response.
    // Without this the client's validator is ignored and every periodic
    // manifest poll re-transfers the whole file.
    if (inm && !isPartial && etagMatches(inm, object.httpEtag)) {
      return new Response(null, {
        status: 304,
        headers: {
          ETag: object.httpEtag,
          'Cache-Control': cacheControlFor(key),
          'Access-Control-Allow-Origin': '*',
        },
      });
    }

    // `httpMetadata` is what makes the browser apply our Cache-Control; without
    // it R2 returns its own default (short) and revalidates on every view.
    const headers = new Headers();
    if (object.httpMetadata) {
      for (const [k, v] of Object.entries(object.httpMetadata)) {
        if (k === 'contentType' && v) headers.set('Content-Type', v);
        else if (k === 'cacheControl' && v) headers.set('Cache-Control', v);
        else if (typeof v === 'string') headers.set(k, v);
      }
    }
    if (!headers.has('Content-Type')) {
      headers.set('Content-Type', object.key?.endsWith('.webp') ? 'image/webp' : 'application/octet-stream');
    }
    if (!headers.has('Cache-Control')) {
      headers.set('Cache-Control', cacheControlFor(key));
    }
    // The artwork pack's own contract wins over whatever a previous PUT
    // stored. Without this, an object written with a long max-age would pin
    // the manifest as effectively immutable and clients would never see a
    // new pack.
    if (key.startsWith('artwork/')) {
      headers.set('Cache-Control', cacheControlFor(key));
    }
    headers.set('Access-Control-Allow-Origin', '*');
    headers.set('X-Content-Type-Options', 'nosniff');
    headers.set('ETag', object.httpEtag);

    if (object.writeHttpMetadata) {
      // Persist the long-lived cache headers onto the object so any other
      // delivery path (r2.dev, direct S3 GET) serves them too.
      ctx.waitUntil(
        bucket
          .put(key, object.body, {
            onlyIf: { etagDoesNotMatch: '*' },
            httpMetadata: {
              contentType: headers.get('Content-Type'),
              cacheControl: headers.get('Cache-Control'),
            },
          })
          .catch(() => {}),
      );
    }

    const response = new Response(object.body, {
      status: isPartial && object.range ? 206 : 200,
      headers,
    });

    if (!isPartial && request.method === 'GET' && response.status === 200) {
      // Cache clones must be fully buffered before the stream is handed to the
      // client, otherwise cache.put() rejects a partial body.
      const forCache = response.clone();
      ctx.waitUntil(
        cache
          .put(cacheKey, forCache)
          .catch(() => {}),
      );
    }

    return response;
  },
};