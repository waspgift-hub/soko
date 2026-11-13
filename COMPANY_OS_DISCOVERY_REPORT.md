# Soko Vibe Company OS — Architecture Discovery Report

**Status:** Phase 0 discovery (read-only). No implementation code has been written for the Company OS.
**Prepared:** 2 November 2026
**Repository:** `waspgift-hub/soko`, branch `ui-refresh-2026-11` (HEAD `d417b5d0`)
**Discovery method:** read-only inspection of repository, git history, provider APIs (Render), and prior E2E work in this session.

---

## 1. Verified stack and deployment map

| Component | Location / Provider | Status | Notes |
|---|---|---|---|
| Flutter client | `soko_langu/` (Android + Web) | VERIFIED IN CODE | Flutter 3.41.9 per CI. Firebase Core/Auth/Firestore/Storage/Crashlytics/Performance, OneSignal, Supabase Flutter, media playback, go_router. |
| Main API | `soko_langu/server/` on Render service `soko-langu-server` (free plan, frankfurt, node) | VERIFIED IN PROVIDER | Start: `node src/index.js` from `soko_langu/server`. Health `/health`. Auto-deploy from GitHub `master`. |
| API edge | `soko_langu/cf-worker/` (Cloudflare Worker) | DOCUMENTED ONLY | `worker.js` + `wrangler.toml` present. Actual deployment not independently verified in this session. |
| Public web | `soko_langu/server/landing/` + Cloudflare Pages (per docs) | INFERRED | Static landing served by Express at `/`. Cloudflare Pages usage not verified. |
| Database (document) | Firebase Firestore project `soko-langu` (project id `sokonimoko-8c171-a8d14`) | VERIFIED IN PROVIDER | Collections: users, products, transactions, deposits, orders (none), wallets, flash_sales, notifications, etc. Marketplace is effectively empty (0 products, 0 orders, 0 sellers). |
| Identity | Firebase Auth | VERIFIED IN PROVIDER | Email/password + phone OTP. Custom tokens mintable via service account. |
| Object storage | Cloudflare R2 (env vars present) | DOCUMENTED ONLY | `R2_*` env vars in config template. Not verified in this session. |
| Cache/queue | Redis (ioredis/BullMQ) | DOCUMENTED ONLY | Referenced in server code and config. Not verified live. |
| SMS | Meseji (primary) + NotifyAfrica (fallback) | VERIFIED IN PROVIDER | Meseji sender `MESEJI` approved; account balance 0 SMS currently. NotifyAfrica sender `137` not approved. |
| Email | Resend (preferred) + SMTP + Cloudflare Email | VERIFIED IN PROVIDER | Resend key present on Render; delivery confirmed in this session. |
| Push | OneSignal | DOCUMENTED ONLY | Referenced in server code. |
| Payments | ClickPesa (USSD push + BillPay) | VERIFIED IN PROVIDER | Client ID + API key updated on Render; USSD push succeeded (`depmvz5lj4bj78ov2`, ref `LCPCAPZBB6F62F`, SETTLED). Webhook delivery not confirmed. |
| Analytics/crash | Firebase Crashlytics/Performance | DOCUMENTED ONLY | Dependencies present. |
| Supabase | `supabase_flutter` in pubspec | INFERRED | No `supabase/` directory at repo root. Likely legacy or unused. Needs verification. |
| Prisma/PostgreSQL | Claimed in prompt; `soko_langu/server/prisma/` does NOT exist | VERIFIED (absent) | Prompt's claim of Prisma 5 under `soko_langu/server/prisma/` is incorrect for this repo state. No Prisma schema found. Database ownership needs re-verification. |
| `payment-system/` | Separate Express + Prisma project | VERIFIED IN CODE | Has its own `render.yaml`, `prisma/`, `src/`. Overlap with main server payments unverified. Likely experimental/duplicate. |
| `wallet_app/`, `wallet_worker/`, `offline_ussd/`, `music_api/` | Top-level dirs | VERIFIED IN CODE (present) | Purpose and deployment status unknown. |
| `soko_langu/functions/` | Firebase Cloud Functions | VERIFIED IN CODE (deleted in working tree) | Deleted in current working tree; may be legacy. |

## 2. Conflicting deployment descriptions (verified)

- **Root `render.yaml`** (free plan, `soko-langu-server`, `node src/index.js`) matches the live Render service `soko-langu-server` (free plan, frankfurt). This is the active blueprint.
- **`soko_langu/server/render.yaml`** (starter plan, `soko-langu-api` + worker) is aspirational and NOT connected to production. Do not apply both.
- **Root `Dockerfile.prod`** references root-level `package.json`/`prisma/`/`src/` which do not exist at root. Treat as stale.
- **CI** (`.github/workflows/build.yml`) runs Flutter analyze/test + web build + Android release on push to `main`/`master`, conditional on signing secrets.

## 3. Existing admin/HR/project/finance capabilities to reuse

Inspection shows the existing server already has:
- Admin routes (`/api/v1/admin/*`, `/api/admin/*`) with `authenticateAdmin` (x-admin-secret gate).
- Settings service with DEFAULTS, safeMerge, masked reads (`/api/v1/admin/settings`).
- Auth, KYC, payments, orders, wallet, escrow, disputes, refunds, moderation, notifications, search, AI chat, agent, engagement (daily campaign), reconciliation, fraud checks.
- Notification orchestrator/worker, mailer (Resend/SMTP/Cloudflare), SMS service (Meseji/NotifyAfrica), push (OneSignal).
- Cron endpoints: `/api/v1/cron/daily-engagement`, `/api/orders/cron/auto-release`, `/api/engagement/cron/daily-engagement`.
- Finance runner with BullMQ-style queue scheduling (`ensureFinanceSchedule`).

**No existing Company OS, HRM, project/task management, calendar, or document repository module was found.** These would be new bounded modules.

## 4. Data source-of-truth matrix

| Domain | Source of truth | Notes |
|---|---|---|
| Users/identity | Firebase Auth + Firestore `users` | UID is Firebase UID. |
| Products/listings | Firestore `products` | Empty in production. |
| Orders/transactions | Firestore `transactions`, `orders` | Empty orders. |
| Wallets/deposits | Firestore `wallets`, `deposits`, `walletTransactions` | Deposit flow verified end-to-end. |
| Escrow | Firestore (escrow collections) | Not exercised in E2E (no sellers/products). |
| Notifications | Firestore `notifications` | |
| Settings | Firestore `app_settings` (admin settings) | |
| Marketplace analytics | Firestore aggregates | |

**No PostgreSQL/Prisma schema exists in this repo state.** The prompt's assumption of Prisma 5 + PostgreSQL is not verified for the current codebase. If Company OS needs relational storage, it must be provisioned new (or an existing external DB verified).

## 5. Duplicate/stale/conflicting findings

1. **Two render.yaml files** with conflicting plans (free vs starter). Only root is live.
2. **Root Dockerfile.prod** references non-existent root paths. Stale.
3. **`payment-system/`** is a separate Express+Prisma project; production usage unverified. Likely duplicate/experimental.
4. **`supabase/` directory absent** at root; `supabase_flutter` dependency present in pubspec. Likely legacy/unused.
5. **`soko_langu/functions/`** deleted in working tree (Firebase Cloud Functions). May be legacy.
6. **Multiple landing pages** and `hosting/` directory; unclear canonical web deployment.
7. **Legacy `index.js`** vs active `src/index.js` entrypoint. Active is `src/index.js`.
8. **`commerce-store.js`** had merge damage (fixed in this session locally; not deployed).
9. **Feature-compat.js** had duplicate `const user` and `.exists`/`.data()` misuse on `getDocument` (fixed locally).
10. **50 unreachable Flutter files** moved to `_attic/unused_2026-11/`.

## 6. Security and privacy gaps observed

- Admin gate uses `x-admin-secret` header only (no Firebase path). Single shared secret.
- `MESEJI_SENDER_ID`, `NOTIFY_AFRICA_SENDER_ID=137` (not approved), `CLICKPESA_*`, `ADMIN_SECRET`, `CRON_SECRET` all present on Render. Values not inspected.
- Secrets printed in prior chat sessions (Render API key, ClickPesa keys, Meseji key, Firebase service account). **Must be rotated.**
- Logs may contain phone numbers (masked in some places, raw in others). Needs audit.
- No evidence of MFA/step-up for admin actions beyond shared secret.
- Firestore rules not reviewed in this session (file present but not inspected).
- No Company OS data boundary exists yet.

## 7. Test and CI baseline

- **Flutter analyze:** 0 errors, 99 infos (after this session's fixes).
- **Flutter test:** 529/529 passed.
- **Server unit tests:** 680 tests, 666 pass, 14 fail (wallet-deposit NumericIncrementTransform expectations; pre-existing).
- **Live E2E (public, read-only):** 65/65 passed against `api.sokovibe.co.tz`.
- **Authenticated E2E:** 14 pass, 9 fail (mostly expected 404s for non-seller account; some wrong URLs).
- **CI:** `.github/workflows/build.yml` runs Flutter analyze/test + web build + Android release on push to `main`/`master`.

## 8. Recommended architecture (with alternatives and trade-offs)

### Recommended: Modular monolith on Firebase (Firestore + Firebase Auth)

Per founder direction, Company OS will use **Firebase/Firestore** instead of PostgreSQL. This keeps one data platform, one identity provider and one set of SDKs, and avoids provisioning a new database.

- **Frontend:** Flutter Web console (reuses existing Flutter stack, consistent with founder's "simple UI" preference). Alternative: a lightweight web admin — adds a new framework, not recommended now.
- **Backend:** a separate Node/Express service on Render (blast-radius isolation) sharing only Firebase Auth. It exposes `/api/company/*` and talks to Firestore via a dedicated service account with least-privilege (Company OS collections only).
- **Data:** a **separate Firebase project** is strongly preferred for isolation (different service account, different security rules, different billing). If cost is a concern, a **separate collection namespace with a strict prefix** (e.g. `company_*`) plus Firestore security rules and a dedicated least-privilege service account on the SAME project is an acceptable first step, provided security review approves it. The Company OS must never query or mutate marketplace collections (`users`, `products`, `orders`, `transactions`, `wallets`, etc.) directly — only via the marketplace's authenticated APIs.
- **Auth:** reuse Firebase Auth (verified, working). Mapping stored in Firestore `company_memberships` collection: `{ firebase_uid, company_role, legal_entity_ids[], status, mfa_verified }`. Do not create a second auth system.
- **Integrations:** Soko Vibe marketplace integration via authenticated scoped APIs (main server already exposes admin/analytics endpoints). No direct DB access.
- **AI:** assistive only. Use existing AI chat infrastructure (`/api/ai/chats`) as a reference pattern, but with a separate permission-filtered retrieval layer and an explicit allowlist for autonomous actions.
- **Jobs:** Firebase Cloud Scheduler / scheduled GitHub Actions / Render cron for daily reports. BullMQ/Redis only if already provisioned.

### Trade-offs
- Firestore is document-oriented; financial double-entry (journal entries, immutable postings) must be modeled carefully (subcollections + transactions). Acceptable for the scale; revisit if accounting complexity exceeds Firestore's transaction limits.
- Reusing the same Firebase project couples Company OS availability to marketplace Firebase, but a separate project mitigates this. Recommend separate project for production.
- Flutter Web keeps one codebase but may be heavy for an admin console; acceptable given existing expertise.
- Cost: Firebase Blaze plan (pay-as-you-go) required for Cloud Functions/scheduled jobs; Firestore reads/writes billed. Estimate must be confirmed against current Firebase pricing before commitment.

## 9. Phased implementation plan

- **Phase 0 (done):** Discovery report (this document).
- **Phase 1 (1-2 weeks):** Founder approval of architecture + provisioning (Firebase project/namespace, DNS `company.sokovibe.co.tz`, secrets). Set up Company OS skeleton: auth mapping, RBAC, audit log, settings, company/legal-entity setup wizard. No marketplace integration yet.
- **Phase 2 (2–3 weeks):** Employee/HRM module (profiles, org chart, leave, onboarding/offboarding), project/task management (Kanban/list/calendar, milestones), company calendar.
- **Phase 3 (2–3 weeks):** Finance module (chart of accounts, budgets, invoices, expenses, reconciliation) with double-entry journal and approval limits. Marketplace finance integration (read-only aggregates).
- **Phase 4 (2 weeks):** Document repository, contracts, CRM/procurement/inventory (basic).
- **Phase 5 (2 weeks):** AI Company Assistant (permission-filtered RAG), controlled automation engine (Level 0–1 only), reporting (daily/weekly/monthly).
- **Phase 6 (ongoing):** Advanced reporting, self-healing playbooks (Level 2 with approval), compliance, hardening.

## 10. Unknowns requiring founder decision (decision register)

1. **Legal entity details:** company name, registration number, tax references, fiscal year, shareholders. (Cannot be invented; setup wizard required.)
2. **Commercial policy:** platform commission percentage (currently 0 in code; founder must confirm).
3. **Hosting budget:** Firebase Blaze plan + Render service + DNS. Cost estimate depends on plan choice.
4. **Data residency:** Tanzania data-protection requirements for employee/customer data.
5. **Payroll statutory rates:** must be accountant-reviewed; not to be invented.
6. **AI autonomy level at launch:** recommend Level 0–1 only.
7. **Whether to reuse Firebase Auth or migrate to a dedicated IdP.**
8. **Whether `payment-system/` and `supabase/` are active (production usage unverified).**

## 11. Cost estimate

Not estimated with invented numbers. Recommended next step: founder reviews Firebase Blaze plan pricing (Firestore reads/writes, Cloud Functions, scheduled jobs), Cloudflare DNS (free tier), and Resend/SMS quotas already in use. Firebase free tier (Spark) is sufficient for development; production requires Blaze. Exact figure must be confirmed against current Firebase pricing before commitment.

## 12. Discovery gate

**This report is the Phase 0 deliverable. No Company OS implementation code has been written.**

Per the master prompt's non-negotiable rules:
- Discovery before implementation: satisfied.
- No secrets printed: satisfied (values redacted; only names/lengths checked).
- No destructive production actions taken for Company OS: satisfied. (Prior session actions — ClickPesa key updates, Render env updates, deploy triggers — were for the Soko Vibe marketplace, not Company OS.)

**Authorization required before proceeding to Phase 1.** Please confirm:
1. Approved architecture (modular monolith + Firebase/Firestore + Flutter Web console + Firebase Auth reuse).
2. Approved provisioning (Firebase project/namespace, DNS, secrets) and budget.
3. Approved scope for Phase 1 (skeleton + auth mapping + RBAC + audit + settings + company setup wizard).
4. Confirmation of the 8 decision-register items above (or "proceed with defaults marked TBD").

Until authorization is received, no further code changes will be made for the Company OS.
---

**End of discovery report.**
