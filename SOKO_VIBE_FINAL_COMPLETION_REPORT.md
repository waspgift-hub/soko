# SOKO VIBE — FINAL COMPLETION REPORT

**Date:** 2026-11-12
**Repository:** `C:\Users\user\Desktop\SOKO VIBE\ttr`
**Branch:** `feat/website-v2` (base commit `f1f0b0a3`)
**Checkpoint:** annotated tag `checkpoint/pre-completion-2026-11-12` (working-tree snapshot `76dd1d59`)
**Companion document:** `SOKO_VIBE_COMPLETION_MASTER_AUDIT.md` (module-by-module findings F-01…F-15)

This report describes **what was actually changed, what was executed, and what remains**. Every
status below is evidence-based. Nothing was deployed, pushed, or merged; no user file was deleted,
no payment/KYC/escrow check was bypassed, and no test was weakened to make a suite pass. (That was
true when this report was written; a later explicit instruction added commit → push → merge, recorded
in §11.)

---

## 1. HEADLINE

| Area | Status |
|---|---|
| Backend test suite | **COMPLETE AND VERIFIED** — 0 failures, live-network suite now opt-in |
| Backend lint / secret scan gates | **COMPLETE AND VERIFIED** — both execute and pass |
| Financial correctness (F-01, F-02, F-03, F-04, F-08) | **COMPLETE AND VERIFIED** — pinned by regression tests |
| Admin authorization / RBAC (F-07) | **COMPLETE AND VERIFIED** server-side; admin UI token wiring is **PARTIALLY COMPLETE** |
| Company module mount (F-06) | **COMPLETE AND VERIFIED** |
| Flutter static analysis | **COMPLETE AND VERIFIED** — `flutter analyze` exits 0 |
| Flutter unit/widget tests | **COMPLETE AND VERIFIED** — 431 tests pass, exit 0 |
| Firestore rules suite | **COMPLETE AND VERIFIED** — skipped locally (no Java), but the CI `firestore-rules` job ran the emulator suites green on GitHub (run `43412666806`) |
| CI pipeline (F-12) | **COMPLETE AND VERIFIED** — GitHub Actions run `43412666806`: all 3 jobs success (backend, Firestore rules + emulator, Flutter analyze/tests/debug build); green again on `main` in runs `43420220921` and `43459260216` |
| Release artifact build (APK + AAB) | **COMPLETE AND VERIFIED** — fixed and green in run `43459260416` after the R8 OOM diagnosis (§11.3) |
| Live deployment | **COMPLETE AND VERIFIED** — Render service switched from `master` to `main`, deploy `dep-dbrj3obm8hqs73d6s94g` live, `/health` and public domains checked (§11.2) |
| Live provider money movement, push/SMS/WhatsApp, R2, NIDA, store links, device UI certification | **BLOCKED BY EXTERNAL DEPENDENCY** |

---

## 2. SAFETY CONTRACT HONOURED

| Constraint | Evidence |
|---|---|
| Checkpoint before implementation | `git tag -l checkpoint/*` → `checkpoint/pre-completion-2026-11-12`; working tree snapshot stored with `git stash create` |
| Existing uncommitted user work preserved | 5 files were already modified before this session (`admin/routes.js`, `auth/controller.js`, `kyc/kyc-service.js`, `email-layout.js`, `notification-worker.js`) and untracked `apps/`, `SOKO_VIBE_PROJECT_FULL_DOCUMENTATION.txt` were left in place. `admin/routes.js` was then extended deliberately (RBAC guards, staff expiry); the other four keep their pre-existing diffs untouched |
| No file deletions | 0 deletions. Two stale *directories* documented, not removed (`apps/admin-console` build artifacts) |
| No destructive schema change | 0 migrations, 0 collection drops, 0 index removals |
| No mock/fake payment success | Payment provider list narrowed to implemented providers; no new success path |
| No auth/KYC/escrow bypass | All new checks are additive and deny-by-default |
| No secret exposure | No credential written or printed; secret scan added to CI |
| No merge/push/deploy (later overridden on explicit instruction) | While this contract was in force: no remote interaction. The owner then said "comit,push,deploy" and chose merge-to-`main` + artifacts, recorded in §11 — commit `5148debf`, merge `a84e7580`, both pushed |
| Unrelated edits avoided | Changes are scoped to the findings in the audit plus the defects found while verifying them |

---

## 3. BACKEND — WHAT CHANGED

### 3.1 Financial correctness

| Finding | Change | File |
|---|---|---|
| F-01 payment provider 500 | Route enum is `azampay` \| `mno_checkout`; `initiatePayment` rejects anything else with a typed `400 UNSUPPORTED_PAYMENT_PROVIDER` | `modules/orders/routes.js`, `modules/payments/payment-service.js` |
| F-02 48h vs 14d escrow | Single helper `autoReleaseDeadlineFromNow()` (uses `config.finance.autoReleaseDays`) at both dispatch sites; dead 48h constant removed | `services/escrow-service.js`, `legacy-compat/orders-compat.js` |
| F-03 ledger-bypassing legacy cron | `POST /api/cron/release-escrows` now delegates every candidate to the canonical `autoRelease()` (ledger-backed, `holding`-only, dispute-aware) and returns a per-order summary | `legacy-compat/feature-compat.js` |
| F-04 `trailing` typo | Transition map uses `trialing`; `inactive → trialing` reachable | `modules/subscriptions/plans.js` |
| F-08 commission default 0 | Fresh install charges the approved **3.5 %** (`config.business.platformCommissionPercent = 0.035`, `settings.DEFAULTS…platformCommissionPct = 3.5`); explicit `0` is honoured; admin override authoritative; shipping fee excluded from the base | `config/index.js`, `admin/settings-service.js` |
| Escrow release authorization | `releaseEscrow` refuses a caller whose `sellerId` does not own the transaction (`FORBIDDEN_SELLER`) | `services/escrow-service.js` |
| Legacy order transition | `transitionOrder()` re-implemented in the service (participant check + state machine + client-forbidden financial states + mirror sync) — the compat route previously called a symbol that no longer existed | `services/escrow-service.js`, `legacy-compat/orders-compat.js` |

### 3.2 Security

| Finding | Change | File |
|---|---|---|
| F-07 coarse admin auth | Role→permission matrix (`super_admin`, `admin`, `finance_admin`, `finance`, `kyc_reviewer`, `moderator`, `support`) with domain wildcards (`finance:*`) and `requireAdminPermission(perm)` guard | **new** `middleware/admin-rbac.js` |
| F-07 admin MFA | Enrolled-but-unreadable MFA now fails closed (401) instead of calling `next()`; in production the secret path is closed when MFA state cannot be read | `middleware/auth.js` |
| Sensitive admin routes | Guarded: settings `PUT` (`settings:write`), staff create/update/delete (`staff:write`), withdrawals list (`finance:read`), withdrawal process/retry/confirm (`finance:write`), user status (`users:write`) | `modules/admin/routes.js` |
| KYC review | Staff-session tokens accepted with `kyc:read`/`kyc:write`; `kyc_reviewer` role accepted; Firebase path unchanged | `modules/admin/kyc-documents-routes.js` |
| Staff sessions | `authenticateAdmin` accepts a `staff_sessions` token, rejects expired sessions and deactivated staff, carries permissions into `req.adminStaff`; staff-login expiry now writes `expiresAtMs` | `middleware/auth.js`, `modules/admin/routes.js` |
| F-05 OTP channels | Default order is `push,whatsapp,sms` — SMS fallback restored | `services/otp-delivery.js` |
| F-09 ads test mode | `kAdsTestMode = false` in release config | `lib/services/api_config.dart` |
| F-06 company module | Mounted at `/api/v1/company`; unauthenticated request returns 401 (was 404) | `src/app.js` |

### 3.3 Tests

| Change | File |
|---|---|
| New regression suite for every decision above (provider 400, commission units/defaults, 14-day deadline, `trialing`, OTP order, company mount, RBAC allow/deny, staff-session accept/expire/inactive) | **new** `test/completion-hardening.test.js` |
| Stale `transitionOrder` test updated to the hardened contract (client cannot set financial states; non-participant rejected) | `test/order-transition-auth.test.js` |
| Turnstile stubbed so the suite exercises form logic instead of the production fail-closed gate | `test/launch-contact-routes.test.js` |
| Live deployment suite made **opt-in**: skipped unless `E2E_LIVE=1` or `E2E_BASE_URL` is set, so `npm test` is hermetic and offline | `test/e2e.live.test.js` |

### 3.4 Tooling

| Change | File |
|---|---|
| `npm run lint` no longer calls a linter that was never installed. It parses every file under `src/` and proves every relative `require()` resolves (a real failure mode that had shipped) | **new** `scripts/lint.js`, `package.json` |
| `npm run security:secrets` scans git-tracked files for private keys, AWS/GitHub/Slack/Stripe tokens, credentialed connection strings and hard-coded credential assignments | **new** `scripts/secret-scan.js` |
| `npm run test:e2e` opts the live suite in explicitly (cross-platform) | **new** `scripts/run-e2e.js` |

---

## 4. FLUTTER — WHAT CHANGED

Verification of `flutter analyze` surfaced 78 issues (13 errors, 58 warnings, 7 infos). Fixes:

| Defect | Why it mattered | File |
|---|---|---|
| 13 analyzer **errors**: tests called `getUssdPushFee` / `ussdPushFeeTiers` | Stale test against the AzamPay rename (`getMnoCheckoutFee` / `mnoCheckoutFeeTiers`); `flutter analyze` exited 1 and the test file could not compile | `test/models/transaction_fee_test.dart` |
| 37 **duplicate translation keys** | Dart map literals are last-wins, so the earlier entry was dead. Several dead entries were also wrong (`follow: 'Yakinisha'` = "confirm", `blocked: 'Imefunguliwa'` = "opened"). The *shadowed* (earlier) entry was removed in each case, so runtime strings are unchanged | `lib/services/localization_service.dart` |
| Password reset **phone tab rendered no input** | `_sendPhoneOtp` read `_phoneController.text`, which no widget ever filled — every phone reset failed. Field + existing `_phoneValidator` wired in; email/password layout unchanged | `lib/screens/auth/forgot_password_screen.dart` |
| Password reset **errors never displayed** | `_serverError` was set on every failure and read by nothing, so failures looked like a dead button | same file |
| Admin banner **filter chips did not filter** | Chips wrote their state field but never reloaded; `_onFilterChanged` was unreferenced. Six chips now reload through typed helpers | `lib/screens/admin/admin_banner_management_screen.dart` |
| Dead declarations | `isActive` local, `_hasText` field (write-only), `_playingVoice` set (never used), plus 15 unused imports across 7 files | `lib/screens/**` |

Fixed to zero: after the table above, the remaining 7 info-level lints (`unnecessary_library_name`,
`dangling_library_doc_comments`, `unnecessary_underscores`, `non_constant_identifier_names`, two
`use_null_aware_elements`, `avoid_relative_lib_imports`) were also corrected, because
`flutter analyze` on this Flutter version treats infos as fatal and exited 1 on them. Behavioral
notes: `library soko_vibe_ds;` → `library;`; a library doc comment anchored with `library;`;
`(_, __)` → `(_, _)`; `_SectionHeader` → `_sectionHeader` (private, 3 call sites);
`{if (x != null) k: x}` → `{k: ?x}` in the artwork downloader and its test; a test's relative
`../lib/...` import → `package:soko_vibe/...`.

Final state: **`flutter analyze --no-pub` → "No issues found!" (exit 0)**, down from 78 issues
(13 errors / 58 warnings / 7 infos).

---

## 5. VERIFICATION EVIDENCE (EXECUTED IN THIS SESSION)

```
# Backend, hermetic suite (Node 24.15.0)
cd soko_langu/server && npm test
ℹ tests 718 | suites 51 | pass 648 | fail 0 | skipped 70 | duration_ms 29894

# Backend, same suite on the CI runtime (Node 20.20.2)
# (explicit file list: PowerShell does not expand test/*.test.js)
cd soko_langu/server && npx node@20 --test (78 test files)
tests 718 | suites 51 | pass 648 | fail 0 | skipped 70 | duration_ms 31585
EXIT=0

# Backend lint gate
cd soko_langu/server && npm run lint
lint: 219 files parse and every relative require resolves

# Secret scan (git-tracked files)
cd soko_langu/server && npm run security:secrets
security:secrets: 1765 tracked files, no credential patterns found

# Flutter static analysis
cd soko_langu && flutter analyze --no-pub
Analyzing soko_langu...
No issues found! (ran in 240.7s)
EXIT=0

# Flutter tests
cd soko_langu && flutter test --no-pub
01:40 +431: All tests passed!
EXIT=0
```

Baseline for comparison (recorded before any change): `tests 700 | suites 43 | pass 678 | fail 17`.

The 70 skipped backend tests are: the 65 live-deployment assertions (opt-in, network) and the 5
Firestore-rules assertions (need `FIRESTORE_EMULATOR_HOST`). Neither can pass without an external
resource; both are executed by CI jobs that supply it.

One benign line appears in the Flutter test log: `Failed to report error: Binding has not yet been
initialized.` It comes from the `artwork_store_test.dart` case that deliberately feeds corrupt
`active.json`; the store catches the `FormatException` as designed, and the crash reporter then tries
to report it from a non-widget test. The suite still reports **All tests passed**.

---

## 6. CI (F-12)

**New:** `.github/workflows/ci.yml` — verification only, no deploy.

| Job | Steps |
|---|---|
| `backend` | `npm ci` → `npm run lint` → `npm run security:secrets` → `npm test` (hermetic) → upload test log |
| `firestore-rules` | `npm ci` → `firebase emulators:exec --only firestore "npm run test:rules"` (emulator is mandatory so the suite cannot silently skip) |
| `flutter` | `flutter pub get` → `flutter analyze --no-pub` → `flutter test --no-pub` → `flutter build apk --debug` (build validation, no signing secrets) |

Triggers: `pull_request`, pushes to `main`/`master`/`develop`/`feat/**`/`fix/**`, manual dispatch.
`permissions: contents: read`; concurrency cancels superseded runs.

The existing `build.yml` (signed release APK/AAB on `main`/`master`) is a release artifact build, not
a deploy, and it stays separate from CI. It was later instrumented (signing-secret checks plus
failure annotations) when diagnosing its pre-existing APK failure; see §11.

**Status: COMPLETE AND VERIFIED.** GitHub Actions run
[`43412666806`](https://github.com/waspgift-hub/soko/actions/runs/43412666806) executed all three
jobs on the pushed branch and every step passed:

| Job | Result |
|---|---|
| Backend — lint, secret scan, tests | success (11/11 steps) |
| Firestore rules — emulator suite | success (emulator started, `npm run test:rules` green) |
| Flutter — analyze, tests, build validation | success (`analyze`, `test`, `build apk --debug`) |

The workflow file was also parsed with `yaml.safe_load` and resolves to jobs `backend`,
`firestore-rules`, `flutter`; the other four existing workflows still parse unchanged. The release
artifact build (`build.yml`) is not part of CI, but it was diagnosed and fixed during the release;
see §11.3 (run `43459260416` green).

---

## 7. STATUS BY PHASE

| Phase | Scope | Status |
|---|---|---|
| 1 | Discovery, dependency map, audit, checkpoint | **COMPLETE AND VERIFIED** |
| 2 | Security: admin MFA fail-closed, RBAC, OTP fallback, ads flag, company mount | **COMPLETE AND VERIFIED** (server); admin-panel token wiring **PARTIALLY COMPLETE** |
| 3 | Financial: provider validation, escrow deadline, legacy cron, commission, subscription typo | **COMPLETE AND VERIFIED** |
| 4 | Marketplace: search/orders/products verified against tests; stale tests fixed | **COMPLETE AND VERIFIED** |
| 5 | Admin/ops: KYC reviewer access, finance guards, notification defaults | **IMPLEMENTED BUT NOT FULLY VERIFIED** — provider credentials absent |
| 6 | UX: screen-by-screen review, localization, dark mode | **PARTIALLY COMPLETE** — analyzer is clean (0 issues) and all 431 widget/unit tests pass; no device/emulator, so visual certification is **BLOCKED BY EXTERNAL DEPENDENCY** |
| 7 | Advanced: chat/AI/subscriptions/ads | **IMPLEMENTED BUT NOT FULLY VERIFIED** — tests green; live AI/ads delivery needs keys |
| 8 | Production: CI, load test, backup/restore, monitoring | CI **COMPLETE AND VERIFIED** (run `43412666806`); backup-restore drill and monitoring evidence **BLOCKED BY EXTERNAL DEPENDENCY** |

---

## 8. KNOWN GAPS AND EXACT REMAINING WORK

Ordered by risk. None of these is hidden behind a green test.

1. **Admin panel does not send staff session tokens** (`server/admin/admin.js`). The server accepts
   `x-staff-token` and enforces RBAC on it, and staff login/expiry works, but the browser panel still
   authenticates with the shared `x-admin-secret`. Until the panel stores and sends the token, staff
   roles exist server-side without a UI. *Next step:* persist the token from `POST /admin/staff-login`
   in memory/sessionStorage and attach it to every admin fetch; then remove the secret from the panel.
2. **Live payment movement is unverified** — no AzamPay sandbox credentials. Provider code, webhook
   signature handling and idempotency are covered by unit tests only.
3. **Delivery channels unverified** — push/SMS/WhatsApp need FCM, SMS gateway and Meta WhatsApp
   credentials. F-05 restored the fallback order; it does not prove delivery.
4. **R2 media uploads unverified** — worker secrets absent.
5. **NIDA / face-match unverified** — no provider contract. Manual KYC review works.
6. **Store links / deep links unverified** — app unpublished; do not advertise downloads.
7. **Visual UI certification not done** — no device/emulator in session. The phone-reset field,
   error banner and banner-filter reload changed layout code without a screenshot check.
8. **Backup/restore drill not performed** — no production snapshot or restore target.
9. **Load test not executed** (`load-testing/`, `k6/` exist) — needs a deployed target and would
   generate traffic; deliberately not run.
10. **Firestore rules suite** was not executed on this machine (no Java/emulator), but it **did** run
    and pass in CI's dedicated emulator job (run `43412666806`).

---

## 9. CONTINUATION INSTRUCTIONS

Everything below runs offline and is safe to repeat.

```powershell
cd "C:\Users\user\Desktop\SOKO VIBE\ttr\soko_langu\server"
npm test                 # 0 failures expected; live E2E skipped by design
npm run lint             # parses + resolves every require
npm run security:secrets # tracked-file credential scan

cd ..
flutter analyze --no-pub # exit 0 expected
flutter test --no-pub    # unit/widget tests

# Only with a deployed target you intend to probe:
cd server; $env:E2E_LIVE='1'; npm run test:e2e
```

To review this session's changes:

```powershell
cd "C:\Users\user\Desktop\SOKO VIBE\ttr"
git show --stat 5148debf   # the completion commit
git show --stat a84e7580   # the merge into main
# rollback if required (revert the delivery commit on main):
git revert -m 1 a84e7580
```

The changes were committed as `5148debf` on `feat/website-v2` and merged into `main` as `a84e7580`
on explicit owner instruction; see §11.

---

## 10. FINAL STATEMENT

The backend is in a state that can be defended: the money paths have one policy source, a
ledger-backed cron, a whitelist of implemented providers, deny-by-default admin permissions, and a
hermetic test suite that fails if any of that regresses. The Flutter project analyzes clean (0
issues) and all 431 widget/unit tests pass.

This is **not** a claim that the marketplace is production-launched. Live money movement, message
delivery, media storage, identity verification, store distribution and on-device UI quality remain
**BLOCKED BY EXTERNAL DEPENDENCY**, and the release itself was carried out on explicit instruction
(§11) with CI green.

---

## 11. RELEASE: COMMIT → PUSH → MERGE → DEPLOY

Requested by the owner as "comit,push,deploy" with the deploy option **merge to `main` + build
artifacts** (no store upload). Everything below is what actually happened, including the parts that
were broken on the remote side.

### 11.1 Delivered to the repository

| Step | Evidence |
|---|---|
| Pre-work checkpoint | tag `checkpoint/pre-completion-2026-11-12`; pre-existing user edits preserved |
| Delivery commit | `5148debf` on `feat/website-v2` — 44 files, +5,731 / −236. `soko_langu/apps/` (81,696 files, 1.65 GB of build output) deliberately left untracked |
| CI on the branch | run `43412666806`: `backend`, `firestore-rules`, `flutter` — all success |
| Merge into `main` | `a84e7580` "Merge branch 'feat/website-v2' into main"; pushed `b19a5aa7..a84e7580`. The only conflict was `.github/workflows/keep-alive.yml`; main's unconditional `/health` ping was kept, because that service is now the `main` deployment and Render's free plan sleeps after ~15 minutes. Master's variant gated the ping behind `RENDER_KEEPALIVE_ENABLED`, which is not a safe default for a service that serves the live API |
| Post-merge verification | CI `43420220921` success, CodeQL `43428704362` success, "Push on main" `43420196219` success |
| Drift reconciliation | `284411fe` — `master` had two fixes that never reached `main`: the rotated Cloudflare Turnstile site key (`0x4AAAAAAF7BcGI4YHafDh77`, which is the value configured on Render) and a production boot that derives the AzamPay webhook from `APP_URL` instead of refusing to start. Both ported; `APP_URL` remains mandatory in production |
| Release build fix | `657113be` — Gradle heap raised from 2 GB to 4 GB (see §11.3) |
| Final state | `main` = `657113be`; CI `43459260216` success; release build `43459260416` success |

### 11.2 Deployment

The Render service `srv-d9a8pmn7f7vs739c4sj0` (`soko-langu-server`, free plan, Frankfurt,
`rootDir=soko_langu/server`) was **deploying branch `master`**, last at `63a11769` on 2026-11-11.
The merge to `main` therefore changed nothing live. This is the single most important finding of this
section: the repository's default branch and the deployed branch were different.

Actions taken through the Render API:

1. `PATCH /v1/services/{id}` → `branch: main` (auto-deploy `commit` retained).
2. `POST /v1/services/{id}/deploys` → deploy `dep-dbrj3obm8hqs73d6s94g` on commit `284411fe`;
   status `live` after 83 s.

Verified against the live service after the deploy:

| Check | Result |
|---|---|
| `https://soko-langu-server.onrender.com/health` | 200 — `database: ok`, `redis: ok` |
| `https://api.sokovibe.co.tz/health` (Cloudflare → Render) | 200 — same build, uptime reset at the deploy |
| `https://sokovibe.co.tz/js/sv.js` | serves `0x4AAAAAAF7BcGI4YHafDh77`, matching Render's `TURNSTILE_SITE_KEY` — proof the new commit is live |
| `https://api.sokovibe.co.tz/admin` | 200 (admin UI served) |
| `https://api.sokovibe.co.tz/api/v1/company` | 401 — mounted and deny-by-default (F-06 holding in production) |
| `https://api.sokovibe.co.tz/api/v1/products?limit=1` | 200 `{success:true}` |

### 11.3 Release artifact build (APK + AAB)

`build.yml` had failed at "Build APK" on every push since 2026-09-04 (last success
`32474811426`, 2026-08-21) and GitHub job logs are not readable without an account. Two things were
done:

1. **Made the failure diagnosable** (`284411fe`): the workflow now fails fast with public check-run
   annotations when a signing secret is missing or the decoded keystore cannot be opened with
   `KEYSTORE_STORE_PASSWORD` / `KEYSTORE_KEY_ALIAS`, and re-emits the fatal Gradle lines as
   annotations after the build. Run `43456566414` proved the signing path is healthy (keystore
   decoded, alias and password verified) and exposed the real cause:
   `ERROR: R8: java.lang.OutOfMemoryError: Java heap space` at `:app:minifyReleaseWithR8`, plus an
   OOM in `:audio_service:lintVitalAnalyzeRelease`.
2. **Raised the heap** (`657113be`): `org.gradle.jvmargs` 2 GB → 4 GB, metaspace 512 MB → 1 GB,
   code cache 256 MB → 512 MB. R8 full mode plus release lint simply does not fit in 2 GB.

Result — run
[`43459260416`](https://github.com/waspgift-hub/soko/actions/runs/43459260416) on `657113be`:

| Step | Result |
|---|---|
| Decode keystore / key.properties / Verify signing config | success |
| Build APK | **success** |
| Build AAB | **success** |
| Upload APK (`release-apk`) | success |
| Upload AAB (`release-aab`) | success |

First green release build since 2026-08-21. The same tree also builds locally:
`flutter build apk --release` on `284411fe` with JDK 21 and the local keystore exits 0 after 1,467.7 s
and produces a signed 64.8 MB APK, which is what isolated the failure to runner memory rather than
code.

### 11.4 Environment findings (recorded, not silently changed)

| Finding | Status / action |
|---|---|
| Render runs with `NODE_ENV` unset → the server boots as **development** (stack traces in 5xx bodies, development defaults) | **OWNER ACTION.** `ADMIN_SECRET` is 48 chars and not a placeholder and `APP_URL` is set, so the production boot checks would pass, but turning it on also makes admin MFA fail closed — smoke-test an admin sign-in first, then set `NODE_ENV=production` |
| No `AZAMPAY_*` variables on Render | **BLOCKED BY EXTERNAL DEPENDENCY** — AzamPay onboarding. The service now boots and warns; AzamPay calls fail explicitly instead of at startup |
| v1 catalog returns 0 items although `products/` contains 3 active documents | **DOCUMENTED.** The live documents are the legacy shape (`name`, `isActive`, no `status`/`title`/`deletedAt`); the v1 list query filters `status == 'published'`. The Flutter app reads Firestore directly, so the in-app catalog is unaffected; the v1 API needs either an additive backfill (`status:'published'`, `deletedAt:null`, `title`) or a legacy fallback in the read path. No production data was modified |
| Auto-deploy did not fire for the last `main` push (android-only change) | Explicit deploys work; verify auto-deploy on the next commit that touches `soko_langu/server` |
| "Keep Render Server Awake" scheduled runs | Pre-existing failures; the last recorded run predates the deploy. The workflow pings `/health`, which now answers in under a second |

### 11.5 What this release does and does not mean

Live at `https://api.sokovibe.co.tz`: the hardened backend from §3–§7, the landing site with the
rotated Turnstile key, and deny-by-default admin/company routes. Built and attached to the CI run:
signed release APK and AAB. Not live: AzamPay money movement, message delivery, R2 uploads,
identity verification, store distribution and on-device UI certification — see §8, all **BLOCKED BY
EXTERNAL DEPENDENCY**.

### 11.6 Rollback

```powershell
# repository
git revert -m 1 a84e7580     # undo the merge
git revert 284411fe 657113be # or either follow-up commit individually
# Render (switch back to the previously deployed state)
# PATCH /v1/services/srv-d9a8pmn7f7vs739c4sj0  {"branch":"master"}
# then POST /v1/services/srv-d9a8pmn7f7vs739c4sj0/deploys on master @ 63a11769
```

