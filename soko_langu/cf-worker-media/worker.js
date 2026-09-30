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
const BUCKETS = [
  { prefix: 'images', binding: 'IMAGES' },
  { prefix: 'videos', binding: 'VIDEOS' },
  { prefix: 'thumbnails', binding: 'THUMBNAILS' },
  { prefix: 'backups', binding: 'BACKUPS' },
];

const IMMUTABLE = 'public, max-age=31536000, immutable';
const ONE_HOUR = 'public, max-age=3600';

function bindingFor(key) {
  const seg = key.split('/')[0];
  const hit = BUCKETS.find((b) => b.prefix === seg);
  return hit ? hit.binding : null;
}

function errorResponse(status, message) {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
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

    const bindingName = bindingFor(key);
    if (!bindingName) return errorResponse(404, 'unknown_media_namespace');

    const bucket = env[bindingName];
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

    if (!isPartial && request.method === 'GET') {
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
      headers.set('Cache-Control', key.startsWith('videos/') ? ONE_HOUR : IMMUTABLE);
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