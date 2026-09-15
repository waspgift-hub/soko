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
| B | ~100k | pagination + indexes + caching (this PR) |
| C | ~1M | horizontal replicas + workers + replicas |
| D | ~10M | read replicas + CDN + regional sharding |

Each tier is a separate PR; nothing here pretends to reach 10M alone.