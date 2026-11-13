# Soko Vibe — Cloudflare Edge Worker

Sits in front of the Render API and serves the hot read routes from
Cloudflare's edge (200+ cities) so the origin + Firestore only get hit on
cache misses.

## Edge-cached routes

| Route | TTL | Keyed by |
|---|---|---|
| `GET /api/trust/passport/:sellerId` | 300s | path only (shared across ALL viewers) |
| `GET /api/transaction-status/:orderId` | 15s | path + token |
| `POST /api/search/global-search` | 60s | path + body |
| `POST /api/search/autocomplete` | 90s | path + body |
| `POST /api/search/trending` | 300s | path + body |
| `POST /api/search/most-rated` | 600s | path + body |

Everything else passes straight through (never cached) — mutations, admin,
payments, escrow, auth all go to the origin untouched.

Stale-while-revalidate: an expired entry is served instantly and refreshed in
the background, so a burst of users never thunders into Render.

### Verifying the cache actually works

Every cached route returns an `x-edge-cache` header. Two identical requests must
show `MISS` then `HIT`:

```bash
curl -si -X POST -H 'content-type: application/json' -d '{}' \
  https://api.sokovibe.co.tz/api/search/trending | grep -i x-edge-cache
```

| Value | Meaning |
|---|---|
| `MISS` | cold — fetched from Render, now stored |
| `HIT` | served from the edge; Render never saw the request |
| `STALE` | served from edge while refreshing in background |
| `MISS-ORIGIN-ERROR` | origin returned non-200; **never cached**, so a 429 or 500 expires immediately instead of poisoning the cache for the whole TTL |
| `MISS-NOKEY` | cache key could not be built — degraded to a proxied response |

If a cached POST route keeps returning `MISS`, the cache key is broken, not the
origin. Two rules govern the key and both were violated at one point: the key
Request must be `GET` (the Cache API refuses to store or match anything else —
this is why the four POST search routes were silently never cached and every app
open tripped the origin's 30/min search limiter into 429s), and the key must be
URL-encoded into a path rather than concatenated onto the origin string.

## Edge protections (all in `worker.js`, no dashboard clicks needed)

- **Scanner/probe blocking** — `/.env`, `/.git/*`, `/wp-*`, `*.php`,
  `/phpmyadmin`, `/server-status`, `/actuator`, `/.aws` etc. get a 404 at the
  edge and never touch Render, Firestore, or rate-limit budget.
- **Body cap** — non-GET/HEAD requests declaring `content-length` over 1MB
  (the origin's JSON cap) get a 413 at the edge.
- **Origin timeout** — edge-to-origin fetch aborts at 25s (origin times out at
  20s), so a hung origin can't hold edge requests.
- **Security headers** — every edge response gets HSTS, `nosniff`,
  `referrer-policy`, `permissions-policy`, and `x-powered-by`/`server`
  fingerprint stripping.
- **Optional KV rate brake** — bind a `RATE_LIMIT_KV` namespace (see
  `wrangler.toml`) for a coarse 120 req/min/IP sliding window on uncached
  traffic. KV is eventually consistent, so this is a dampener; the origin's
  Redis/memory limiters stay the source of truth.

## Edge ↔ origin trust (EDGE_SECRET)

The worker sends `x-soko-edge: <EDGE_SECRET>` (a `wrangler secret`, never
committed). The origin only trusts `cf-connecting-ip` for rate-limit keys when
that header matches its own `EDGE_SECRET` env var — otherwise it keys on the
socket IP exactly as before. Setup:

```bash
cd cf-worker
wrangler secret put EDGE_SECRET   # generate: openssl rand -hex 32
```

Then paste the SAME value as `EDGE_SECRET` in the Render dashboard for
`soko-langu-api`. Until both sides are set, everything behaves as today.

## Cloudflare dashboard checklist (one-time, can't be done in code)

- **SSL/TLS → Full (strict)** so edge-to-origin is always encrypted.
- **WAF managed rules ON** + a rate-limiting rule for `/api/v1/auth/*` and
  `/api/v1/payments/*` as a second layer behind the worker/origin limits.
- **Bot Fight Mode** (free tier) for basic bot mitigation.
- **DNS**: `api` CNAME proxied (orange cloud); keep the Render
  `onrender.com` URL out of public docs so attackers can't bypass the edge.

## Deploy (one-time, needs your Cloudflare login)

```bash
npm i -g wrangler
cd cf-worker
wrangler login          # opens browser, signs into Cloudflare account
wrangler deploy
```

Then create a DNS record in the Cloudflare dashboard for `sokovibe.co.tz`:
**Type CNAME, Name `api`, Target `soko-api-edge.<your-subdomain>.workers.dev`, Proxy ON**.

## Verify

```bash
curl -si https://api.sokovibe.co.tz/health
curl -si -X POST -H 'content-type: application/json' -d '{}' \
  https://api.sokovibe.co.tz/api/search/trending | grep -i x-edge-cache
curl -si -H "Authorization: Bearer <token>" https://api.sokovibe.co.tz/api/trust/passport/<sellerId>
# repeat each: the second call must show `x-edge-cache: HIT` and `x-soko-edge: 1`
```

## Point the app at it

Only after the worker is live and the DNS record is proxied, change
`lib/services/api_config.dart`:

```dart
static const String baseUrl = 'https://api.sokovibe.co.tz';
```

(Do NOT ship this change until `curl /health` works through the edge.)

## Routing alternative

To go same-origin on the web app instead of a subdomain, switch the route in
`wrangler.toml` to `sokovibe.co.tz/api/*` and set the web build's base to a
relative `/api` — no CORS, no DNS change.