# Soko Vibe — Server Migration Runbook

Goal: any server hosting (Render, Railway, Fly.io, Vercel, your own VPS, another
provider) must be swappable **in under 15 minutes, with zero user disruption**.
This works because the architecture keeps one stable public face (the Cloudflare
edge) and moves everything else behind env vars.

## Why the app "never notices" a move

```
users ──> api.sokovibe.co.tz (Cloudflare Worker)
              │
              ▼
      soko-api-edge (cf-worker/worker.js)
      origin = $ORIGIN_URL            <── the ONLY thing that changes on a move
              │
              ▼
      your backend instance (Render today)
```

- Users only ever talk to the Cloudflare edge. They never see the backend host.
- The edge caches public reads; on the move day those are served from the edge
  while the backend is offline/booting.
- A move = deploy the same code to the new host, point `ORIGIN_URL` at it.
  Nothing in the app or DNS changes from the user's perspective.

## The 5 moving parts (all env-driven)

| Part | Where it lives now | Env var to change on a move |
|---|---|---|
| HTTP backend | `server/` (Express + Prisma) | `ORIGIN_URL` in `cf-worker/wrangler.toml` |
| Primary DB | Render Postgres | `DATABASE_URL` |
| Read replica | Render Postgres (optional) | `DATABASE_URL_REPLICA` |
| Cache/queue | Upstash/Render Redis | `REDIS_URL` |
| Object storage | Cloudflare R2 | `R2_*` vars |
| Auth | Firebase Auth | `FIREBASE_*` vars (project is portable) |
| Firestore | Firebase | N/A — Firebase is already "the cloud", never moved |
| SMS | Meseji + Notify Africa | `MESEJI_BASE_URL` / `NOTIFY_AFRICA_SMS_BASE_URL` |
| Push | OneSignal | `ONE_SIGNAL_BASE_URL` |
| Payments | ClickPesa | `CLICKPESA_API_URL` |

Because every external service is behind `server/src/config/index.js`, moving
hosts never requires code changes — only new env values on the new host.

## Checklist: zero-downtime move

> The target host must run `server/` with the SAME commit and ONLY fresh env
> values. All data stores below follow the standard "fan-out" pattern: provision
> new, sync, flip env, keep old until verified, cut over DNS/origin last.

### 0. Pre-flight (any time before)
1. `node --check` on every changed file; `npm test` green (202 tests).
2. Push latest to GitHub (Render auto-deploys; your new host can pull too).
3. Back up: Postgres `pg_dump`, Firestore `firebase firestore:export`, R2
   bucket list.

### 1. Provision the new host
- Create a new service running `server/` (same image/commit), set ALL env vars
  from `server/.env.example` + the current Render dashboard values.
- Do **not** point its `ORIGIN_URL` change yet — it's still behind the old one.

### 2. Migrate data (fan-out while both are live)
- **Postgres:** create new Postgres, `pg_dump` on the old → `pg_restore` on the
  new. Verify row counts match.
- **Redis:** it is a pure cache + ephemeral queue. Do NOT migrate it — let it
  re-warm from the DB/edge. New Redis on the new host just starts empty.
- **R2:** same bucket is reachable by any host that holds the keys (regional
  endpoints change only if you also move buckets — see "Data locality" below).
- **Firebase:** nothing to do — Firebase is provider-managed and portable by
  service account JSON (same keys work from any host).

### 3. Cut over (the only "downtime" is zero)
1. Set the new host's env to the PRODUCTION Postgres/R2/Firebase (still the
   old ones — both hosts on the same data).
2. Smoke-test the new host directly: `GET <new-host>/health` returns
   `version: 2.0.0`, `database: ok`, `redis: ok`.
3. Edit `cf-worker/wrangler.toml` → `ORIGIN_URL = "<new-host>"`, deploy the
   worker. The edge now sends all traffic to the new host.
4. Watch `GET /health` for 5 min: uptime climbing, `database.ok`,
   `redis.ok`, no 5xx in Render logs.

### 4. Decommission the old host (AFTER verification, e.g. +24h)
1. Keep the old Postgres as a failback (`DATABASE_URL` can point at it
   instantly if the new DB misbehaves).
2. Once confident, drop the old host. Rollback = flip `ORIGIN_URL` back.

## Rollback (i.e., "the move went wrong")
- **Within minutes:** flip `ORIGIN_URL` back in `wrangler.toml`, redeploy the
  worker (8s). Users never noticed anything because the edge never went down.
- **Data issue:** point the new host back at the OLD Postgres first (both were
  live on the same data during fan-out), then fix and re-cut.

## Free → paid path (no code rewrite)

Everything runs on free tiers today and switches to paid only by env/value, not
by code:

| Resource | Free now | Paid upgrade (same code) | Trigger |
|---|---|---|---|
| Backend | Render free/starter, 1–6 replicas | Same image on Render/Railway/Fly | traffic exceeds free quota |
| Postgres | Render free Postgres | Render Pro Postgres / Neon / Supabase | storage/connections |
| Redis cache | Upstash/Render free | Upstash paid (scales mem+throughput) | Redis saturation |
| Firestore | Spark free (50k reads/day) | Blaze pay-as-you-go + Flame cap | read growth |
| R2 storage | free egress + 10GB | pay-as-you-go | media growth |
| Edge cache | Cloudflare free | Cloudflare paid plan | cache size/queries |
| SMS | Meseji/Notify free credits | paid SMS (same `MESEJI_BASE_URL`) | volume |
| Push | OneSignal free (10k opt-ins) | OneSignal paid | push volume |

Moving any one of these to a paid tier is a **config/deploy change only** — the
code reading `server/src/config/index.js` never changes.

## Data locality note
If you also move to a non-Cloudflare storage backend (e.g. S3 instead of R2),
only update the `R2_*` vars — the S3-compatible SDK (shared with R2) accepts any
S3 endpoint. Find all R2 usage via `rg "R2_|r2" server/src`.

## Monthly DR drill (recommended)
Every month, run steps 0→3 on a new throwaway host to prove the move still works
in <15 min. Keep the throwaway host for 24h then delete it. This catches any
DRIFT (hardcoded values, missing env entry in `.env.example`) before a real move.