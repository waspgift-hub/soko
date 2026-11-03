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
curl -si -H "Authorization: Bearer <token>" https://api.sokovibe.co.tz/api/trust/passport/<sellerId>
# second request ~1s later should show `cf-cache-status: HIT` and `x-soko-edge: 1`
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