# Soko Vibe — Scaling Playbook

How the stack grows from a single instance to thousands of concurrent users.
This is the operational counterpart to the code-level pagination/caching work.

## Current architecture (as of v2.0.0)

- **Express API** (`src/index.js`) on Render, single instance, health `/health`.
- **Firestore** holds products, orders, transactions, notifications, chat,
  flash sales, statuses, reports, payouts. Read-heavy paths hit it directly.
- **Postgres + Prisma** holds users, wallets, sessions, admin tables.
- **Redis (Upstash/ioredis)**: two-tier cache (LRU 500 + Redis), rate limiter
  counters, BullMQ queue, idempotency locks (`SET NX EX`).
- **Flutter app** reads products/categories/orders DIRECTLY via the Firestore
  SDK (client-side). The HTTP API only handles auth, payments, escrow, search.
- **BullMQ finance worker** (`src/workers/index.js`) does autorelease,
  payout expiry, reconciliation, dispute SLA sweeps.

## The 6 levers, in order of payoff

| Priority | Lever | Files | Why |
|---|---|---|---|
| 1 | Firestore pagination | Flutter services | Unlimited `.snapshots()` today; 10M users × 20 docs = 200M reads |
| 2 | Composite indexes | `server/firestore.indexes.json` | Without them Firestore refuses combined queries as data grows |
| 3 | Redis API caching | `search.js`, `trust-compat.js` | Trust passport = 600 reads/req; global-search = 9 reads/req |
| 4 | BullMQ workers | `src/workers/index.js` | Move autorelease + media off the request path |
| 5 | Prisma pool cap | `src/config/database.js` | Per-instance `connection_limit`; scale instances not pool |
| 6 | Horizontal replicas | `server/render.yaml` | 3–6 web replicas behind LB; dedicated worker service |

## Hot paths today

| Path | Reads | Mitigation |
|---|---|---|
| `GET /api/trust/passport/:sellerId` | up to 600 Firestore docs | Redis 5-min cache (`trust-passport:` key) |
| `POST /api/search/global-search` | 3–9 Firestore queries + fuzzy | Redis 60s pipeline cache per query |
| App product/category streams | unbounded | Flutter `.limit()` + cursors (Tier 1) |
| Auto-release cron | sweeps whole `orders` collection | BullMQ idempotent jobs on deadline index |

## Firestore budget guardrails (10M users)

Firestore bills by reads/writes/storage. Guardrails already in place:

- **Client-side pagination** — every product/order/transaction stream uses
  `.limit()` + cursor pagination (never full-collection `.snapshots()`).
- **Client offline persistence enabled** (`lib/main.dart`,
  `Settings(persistenceEnabled: true)`) — SDK serves cached docs on relaunch,
  cutting cold-start Firestore reads.
- **Server-side aggregation off the read path** — trust passport, search and
  catalog reads are Redis/edge cached; the Finance worker batches writes.

Console actions (one-time, dashboard):
1. Billing → Budgets: alert at 50% / 75% / 90% of a monthly Firestore budget.
2. Budget alerts → email notification on each threshold.
3. Flame plan caps the per-project spend ceiling (hard stop, not just alert).
4. Watch the Firestore "Reads" metric daily; a sudden read spike usually means a
   client query lost its `.limit()`.

## Cloudflare edge (cf-worker/)

A Worker proxies the API through 200+ edge cities and serves the hot read
routes without ever reaching Render:

- trust passport/v1 passport 300s, transaction-status 15s, products 30s,
  categories 3600s, search autocomplete 90s, trending 300s, most-rated 600s,
  global-search 60s — stale-while-revalidate.
- Edge cache keys derive from path+query (+ body hash for POST search), never
  from personalized headers, so no cross-user leakage.
- Every mutation/admin/payment/escrow request passes straight through.
- Deploy: `wrangler login && wrangler deploy` from `cf-worker/` (see
  `cf-worker/README.md`). Requires a proxied DNS record `api.sokovibe.co.tz`.

Once live, point `ApiConfig.baseUrl` at the edge URL. The mobile-to-origin
hop becomes edge-to-origin only on cache miss.

## Origin resilience (2026 tier)

Added so the origin survives a 10M-user spike instead of degrading:

- **Cache stampede protection** (`server/cache.js#getOrCompute`): single-flight
  per key — a thundering herd collapses into ONE database query per TTL window.
  Hot catalog routes (`/api/v1/products*`) read through it and invalidate on
  mutation (`catalog:*` keys).
- **Circuit breakers** (`server/src/utils/circuit-breaker.js`): ClickPesa, SMS
  (Meseji + Notify Africa), OneSignal fail fast (503 `PAYMENT_PROVIDER_UNAVAILABLE`
  on open) instead of 15s timeouts piling up.
- **Load shedder** (`server/src/middleware/loadShedder.js`): when the event loop
  lags >1.5s AND heap >512MB the instance answers 503 + `Retry-After` (toggled
  by `SHED_LOAD`) so Render retreats it from the rotation mid-storm.
- **Firestore budget guardrails**: client reads are paginated (`.limit()` +
  cursors); enabled features map to quotas in this doc's tier table.

## Postgres read replicas (Tier D groundwork)

Render Postgres supports dedicated read replicas. The server already routes the
hot public catalog reads (`products`, `categories`) through the replica when one
exists and falls back to the primary when not:

- Set `DATABASE_URL_REPLICA` (Render: your-DB → Read replicas → Create, paste
  the replica's internal URL). Code gate is `database.js#getReadPrisma()`.
- Every write stays on the primary (`getPrisma`); the replica is used ONLY for
  cache-safe catalog reads, so even seconds of lag are invisible behind the
  30s-1h cache TTLs.
- Per-instance pool cap applies to both URLs (`connection_limit=10`).

## Cloudflare regional routing (Tier D groundwork)

`cf-worker` resolves the visitor's continent (`request.cf.continent`) and, when
`REGION_ORIGIN_AF/EU/AS/NA` vars are set, proxies public catalog + search reads
to the nearest regional Render replica. Key guarantees:

- Only **region-agnostic GET/POST** public reads are routable; auth/payment/
  mutation paths always hit the primary ORIGIN so state never splits.
- Cache keys embed the resolved origin, so regions never share a stale entry.
- With no regional vars set (default) everything behaves exactly as today:
  single origin, single cache.

## Firestore index deploy

```
firebase login
cd server
firebase deploy --only firestore:indexes
```

`firestore.indexes.json` declares all composite indexes; deploy once, then
every combined query uses a single index.

## Scaling a release (operational checklist)

1. `flutter analyze` must stay at baseline; build debug APK.
2. `node --check` on every changed server file; `npm test` green.
3. Run `test:e2e` (paced at 2200 ms to stay under the 30 req/min limiter).
4. Push to GitHub — Render auto-deploys master.
5. After deploy: `GET /health` (expect `version: 2.0.0`), `GET /api/trust/passport/:testSeller`.
6. Check Redis hit ratio on `trust-passport:*` — miss only on TTL expiry.

## Honest capacity tiers

| Tier | Ceiling | Requires |
|---|---|---|
| A (now) | ~5k–10k users | current single instance |
| B | ~100k | pagination + indexes + caching (done) |
| C | ~1M | horizontal replicas + workers (done) |
| D | ~10M | read replicas + CDN + regional sharding (next) |

What's already live toward C/D: Render autoscale 1→6, dedicated BullMQ worker,
edge cache at 200+ cities, stampede protection, circuit breakers, load shedder,
every read route paginated. Groundwork for D: `DATABASE_URL_REPLICA` read
replica routing (products/categories), Cloudflare regional-origin routing.
Remaining for true multi-region D: provisioning the actual Postgres read replica
+ regional Render replicas, Firestore per-tenant collections, KV/edge state.