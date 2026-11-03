# Soko Vibe — Reliability & Recovery Runbook

Status date: 2026-10-30. Describes the production stack as it exists in the
repository today (Firestore + Redis + Cloudflare Worker edge + Render). Items
marked **NOT ACTIVE** need infrastructure approval or credentials before they run.

## 1. Current topology (verified in code)

| Layer | Component | Source |
| --- | --- | --- |
| Edge | Cloudflare Worker `soko-api-edge` proxies `api.sokovibe.co.tz` to `ORIGIN_URL` | `soko_langu/cf-worker/wrangler.toml` |
| Origin API | Express app `server/src/index.js` | `soko_langu/server` |
| Background | BullMQ workers (finance, notifications, media) | `server/src/workers/index.js` |
| Data | Firestore via `services/firestore-store.js` and `services/commerce-store.js` | — |
| Cache / locks / queues | Redis (ioredis) | `server/src/config/redis.js` |
| Media | Cloudflare R2 buckets (images, videos, thumbnails, backups, kyc, artwork) | `cf-worker-media/wrangler.toml` |
| Payments | ClickPesa collection + payout, webhooks dedup via commerce-store outbox | `server/src/modules/payments` |

Known gaps: the edge still points at `soko-langu-server.onrender.com`, which is
the free-tier service. The scaled `soko-langu-api` definition in
`server/render.yaml` is not the origin production traffic reaches. Confirm the
Render dashboard before relying on replica counts.

## 2. Recovery objectives (proposed, need owner sign-off)

| Scenario | RPO | RTO | Procedure |
| --- | --- | --- | --- |
| API instance failure | 0 (stateless) | < 5 min | Render restarts the instance; edge retries |
| Worker crash mid-job | 0 (BullMQ keeps jobs in Redis) | < 5 min | Worker restart resumes queued jobs |
| Redis outage | Locks fail closed (503 + Retry-After); money paths stop, not corrupt | Until Redis returns | Restore Redis; jobs resume |
| Firestore accidental deletion | Last export (see §4) | < 4 h | Restore from export into a staging project first |
| Failed deploy | 0 | < 10 min | Redeploy previous commit (§5) |
| Cloudflare edge outage | 0 | Minutes | Point DNS to origin or wait; origin still serves |
| Payment provider outage | 0 | Until provider returns | Circuit breakers return 503 PAYMENT_PROVIDER_UNAVAILABLE; webhook redelivery reconciles |

## 3. Idempotency guarantees (what the code enforces today)

- **Webhooks:** each provider event is claimed by a Firestore transaction
  `create()` on `webhooks/{dedupKey}`. A duplicate delivery returns
  `claimed: false` and is acknowledged without re-applying the business effect.
  Covered by `server/src/services/commerce-store.js#recordWebhookEvent`.
- **Ledger:** `postLedger` and `settleEscrowToSeller` use a deterministic
  ledger doc id (`buildLedgerId`) inside a transaction, so a retry cannot credit twice.
- **Payment and collection flows:** guarded by Redis `requireLock` (fail closed)
  plus status-priority checks in `payment-service.js`.

Known gap: `firestore-store.js` `$transaction` is a buffered overlay that
commits a batch. It is not a serializable read-modify-write. Money code must go
through `commerce-store.js`, not the generic facade. A generic `update()` can
lose concurrent writes.

## 4. Backups (NOT ACTIVE until verified)

The repository previously claimed Postgres backups. There is no Postgres in the
runtime, so `deploy/scripts/backup.sh` backs up nothing that exists and must not
be scheduled.

Required for Firestore (operator action, needs GCP/Firebase project access):

1. Enable scheduled Firestore exports to a Cloud Storage bucket with a
   retention lifecycle rule (for example 30 daily, 12 weekly).
2. Restrict bucket access to a backup service account. Enable object versioning
   and bucket lock where available.
3. Alert on export failure (Cloud Scheduler failure notification or equivalent).
4. Verify with a restore into a **separate staging project**. Never restore into production.

Media (R2): the `soko-vibe-kyc` bucket must never be made public as part of a
backup. Back up it with encryption and presigned access only. Copying product
media to the `soko-vibe-backups` bucket is also **NOT ACTIVE**.

Application config: keep env var **names** in `server/.env.example`. Never copy
secret values into git or logs.

## 5. Rollback

1. Identify the last good commit: `git log --oneline -10`.
2. Render: redeploy that commit from the dashboard (or revert and push, if the
   deploy is auto-from-branch).
3. Edge: if the worker change is at fault, `wrangler deploy` the previous
   `cf-worker` revision.
4. Verify: `GET /health` returns `status: ok`, then one authenticated read and
   one non-mutating order status call.

## 6. Verification checklist after any change

- `npm test` in `soko_langu/server` (currently 676 tests; must stay green).
- `node --check` on every changed server file.
- Smoke: `/health`, `/health/live`, and one `GET /api/v1/products`.
- Payment webhook: replay a recorded event in staging and confirm a single
  ledger effect (second delivery acknowledged as duplicate).

## 7. Not yet implemented (see the delivery report)

- Dead-letter handling for the media, finance and notification queues. Retry
  with exponential backoff (5 attempts, 5s base) is now the default on all three.
  Exhausted jobs stay in BullMQ's failed set (500 retained) for inspection.
- Dedicated readiness endpoint and an in-flight concurrency cap.
- Scheduled Firestore export and restore test (needs credentials).
- Load testing (k6 scripts exist under `soko_langu/k6`; they must be run
  against staging, not production, and need approval for any cost).
