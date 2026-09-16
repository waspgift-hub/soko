# Soko Vibe — Data Domain Ownership Map (Phase A: FREEZE)

Status: Phase A deliverable per MASTER_ARCHITECTURE.pdf §30.
Last verified: September 2026 — every claim below was read from current code.

## 1. Where the ring is (entry points)

| Artifact | Entrypoint | Source of truth |
|---|---|---|
| `package.json` | `main: src/index.js` | v2 (Postgres) |
| `npm start` / Render web | `node src/index.js` | v2 (Postgres) |
| Render worker | `node src/workers/index.js` | v2 (Postgres/Redis) |
| Dockerfile `CMD` | `node index.js` ← **LEGACY, out of ring** | v1 (Firestore) |

The Dockerfile still boots the v1 legacy `index.js` (374 KB). `render.yaml`
does NOT use the Dockerfile (it uses `runtime: node` + startCommand), so
production is not affected today — but anyone who deploys via Docker gets the
legacy stack. This is recorded as a **convergence task** (align `CMD` to
`node src/index.js`) rather than changed blindly, because the legacy image also
boots without Postgres/Redis env vars and a swap could break a Docker-based
rollback path.

## 2. Data domain ownership

Legend: **A** = authoritative, **M** = mirror/compat (to be retired), **C** = client-owned but protected by Firestore rules.

| Domain | Firestore (v1) | Postgres (v2) | Owner today | Target (blueprint) |
|---|---|---|---|---|
| Products catalog | **A** (client reads/writes `products`) | M (`/api/v1/products`, `Product` model) | Firestore (client) | Postgres/API (Phase B/C) |
| Sellers/store | **A** (`users`, `sellerName`) | M (`SellerProfile`) | Firestore | Postgres/API |
| Orders | **A** (`orders`, legacy-compat state machine) | M (`Order` model + presentation mirror) | Firestore (server) | Postgres/API |
| Payments / transactions | **A** (`transactions` via orders-compat) | **A** (`Payment`, `PaymentAttempt`, `EscrowTransaction`, `WebhookEvent`) | Split: Firestore for app flows, Postgres for shop | Postgres/API |
| Escrow | **A** (`orders/status` + finance jobs) | **A** (`EscrowHold`, `EscrowTransaction`) | Split | Postgres/API |
| Wallet / ledger | — | **A** (`Wallet`, `WalletLedgerEntry`, `Withdrawal`) | Postgres | Postgres (already) |
| Payouts | **A** (`payouts` legacy-compat) | M (`PayoutTransaction`) | Firestore (server) | Postgres/API |
| Trust passport | **A** (`users`, trust fields) | **A** (`/api/v1/trust`) | Split | Postgres/API |
| Chat | **A** (`chat_rooms`, `messages`) | — | Firestore (client + server moderation) | Isolated chat service (Phase E) |
| Notifications | **A** (`notifications`, app-facing) | **A** (`Notification` model) | Split | Postgres/API |
| Reviews | **A** (`reviews`) | — | Firestore (client) | Postgres/API (Phase D) |
| Referrals | — | **A** (`Referral`) | Postgres | Postgres (already) |
| Boosts | **A** (`products.isBoosted*` server-owned) | **A** (`Boost`, `Product.boosts`) | Firestore (server) | Postgres/API |
| Moderation/reports | **A** (`reports`, moderation-compat) | **A** (`ModerationReport`) | Split | Postgres/API |
| Feed | **A** (`products` derived) | **A** (`FeedPost`, `Like`, `Comment`, `Save`) | Split | Postgres/API |
| Ads/Analytics | **A** (`ad_views`, `*_analytics`) | — | Firestore (client) | Postgres/API (Phase D) |
| Media | **A** (Cloudinary URLs inside product docs) | **A** (`ProductMedia`, R2 keys) | Split: Cloudinary (client) vs R2 (server) | R2 only (Phase F) |
| KYC / identity | **A** (`users.kyc`, server-owned) | — | Firestore (server) | Postgres/API |

## 3. Server module map (`src/modules`) — verified mount status

`app.js` mounts, in order:

1. `/api/v1/*` — v2 modules, Postgres: auth, users/settings, sellers, orders,
   payments, shipping, handover, wallet, disputes, refunds, media, feed,
   search, share, trust, admin, products, referrals, moderation, reconciliation,
   notifications.
2. `/api` → `legacyShopRouter` — v2-backed checkout/status (Postgres) for the
   web shop SPA, before legacy compat so Postgres wins.
3. `/api` → `legacy-compat` mounts — **mark as compatibility, removal path exists**:
   - payoutsRouter (`/api` + `/api/payouts`) — Firestore payouts
   - deliveryRouter (`/api/orders`) — delivery OTP
   - searchRouter (`/api/search`) — Firestore search
   - notificationRouter (`/api/notification` + `/api/notifications`)
   - featureCompatRouter (`/api`) — incl. cloudinary sign, auth, boost, kyc
   - escrowRouter (`/api/escrow`)
   - ordersCompatRouter (`/api`) — incl. create-marketplace-payment-link,
     transactions/create (Firestore state machine)
   - trustCompatRouter, moderationCompatRouter, adminCompat, adminCompatPublic

## 4. Firestore rules that already enforce server authority

`firestore.rules` deny client writes to: `isAdmin, isSuspended, walletBalance,
sellerBalance, pendingEscrow, totalSales, grossSalesVolume, totalWithdrawn,
isBoosted, boostedUntil, boostTier, kyc, createdAt, lastSaleAt, lastLoginAt`.
Ratings/reviewCount updates are server-or-admin only for products.
Orders catch-all: participant cannot mutate `status` inline (state machine).

## 5. Phase A freeze decisions (this iteration)

1. NO new client-side Firestore commerce writes may be added.
2. New commerce flows MUST target `/api/v1/*` (Postgres).
3. Legacy entry `server/index.js`, `orders.js`, `search.js`, `notification.js`,
   `routes/*`, `helpers/*` remain **frozen** — bug fixes only, no new features.
4. Dockerfile entrypoint divergence → recorded, not force-changed (rollback risk).
5. Removal of any legacy path requires: tests + production verification +
   rollback plan (blueprint §30-G).

5. Lifecycle wiring caveat (B/C finding): buyer cancel/release are NOT safe to
   flip to /api/v1/orders yet — v1 cancel rejects funds-held orders outright
   (no ClickPesa refund yet) and v1 complete settles to the Postgres wallet
   ledger instead of the legacy sellerBalance/ClickPesa payout. Lifecycle
   wiring therefore depends on the wallet/payout converge (candidate 3).
   Dispatch + dispute are flag-safe (state-compatible from IN_ESCROW).
6. User-provisioning enabler: `auth.js` `authenticate` now auto-provisions a
   Postgres `users` row from the Firebase record when missing (mirrors
   legacy-shop `resolveShopBuyer`), so every /api/v1/* call works for an app
   user who never hit the legacy buyer sync. Without this, v1 returned
   401 USER_NOT_FOUND for those sellers and could never be wired client-side.
7. Dispatch wiring done (client): `seller_dispatch_screen.dart` dispatch calls
   `OrderApiClient().dispatchOrder` when `kUseOrdersApi` is on (default off);
   legacy `/api/escrow/dispatch` remains the default. driverPhone/notes have no
   v1 fields yet — revisited at flag flip.
8. Wallet/payout sequencing (B/C finding): the Postgres withdrawal core already
   exists (`wallet-service` `requestWithdrawal`/`processWithdrawal`/
   `confirmPayout` + `/api/v1/wallet/withdrawals`). BUT app sellers' money still
   lives in Firestore `sellerBalance` (release pays it via legacy escrow), and
   the Postgres wallet ledger only accrues from v2 `complete`. Flipping
   withdrawals to the v1 wallet before converging the RELEASE path would expose
   an empty wallet — withdrawal converge must come AFTER release converge.
9. Money-safety fix done: order settlement (`completeOrder` + handover
   `verifyOtpAndComplete` → `releaseEscrowAndSettle`) now calls `ensureWallet(tx)`
   from `wallet-service` instead of the old `if (wallet)` guard. Previously a
   seller with no wallet row completed the order with the credit silently
   skipped — money effectively lost. `requestWithdrawal` also ensures the wallet
   (reports INSUFFICIENT_BALANCE instead of 404). Tested in
   `wallet-settle.test.js` (idempotency + no-wallet regression).
10. Security fix done: handover `issueOtp` returned the plaintext OTP to any
    authenticated caller who knew the order UUID (data exposure). Now gated by
    `assertCanIssueOtp` — only the order buyer or admin may issue; buyer-only
    mirrors legacy Firestore OTP visibility. Tested in `handover-auth.test.js`.
11. Wallet client bridge done: `lib/models/wallet_model.dart` +
    `lib/services/wallet_api.dart` (fetchWallet / fetchWithdrawals /
    requestWithdrawal) behind `ApiConfig.kUseWalletApi = false`. 10 client tests.
    Flip order for sellers: release converge FIRST (§5 item 8), then wallet UIs,
    then retire `/api/payouts/*` legacy reads.
12. Dispute wiring deferred: v1 `disputeOrder` has no evidence field; the app
    record is in Firestore and `DisputeEvidence` is R2-first (blueprint media
    rule). Wiring app dispute to v1 today would drop evidence — leave on legacy
    until the R2 evidence upload path lands (Phase F), then wire and retire.
13. Release-path wire is now UNBLOCKED server-side AND client-side:
    Server: `POST /api/v1/handover/:orderId/otp/issue` (buyer/admin-gated) +
    `POST /api/v1/orders/:orderId/complete { otp }` (atomic settlement via
    `verifyOtpAndComplete`); `ensureWallet` guarantees seller always receives the
    ledger credit; `confirmCollection` already creates the `escrowHold` row for
    app orders at payment time so the wallet settlement never silently skips.
    Client (behind `kUseOrdersApi`): buyer's "Nimepokea" arrival action calls
    `issueHandoverOtp` (returns 6-digit + expiry); seller's OTP form length
    adapts to 6; seller verify posts to `completeOrder(txId, otp)`. When the
    flag flips, legacy Firestore `delivery_otp` + `/api/orders/verify-delivery` +
    Firestore `sellerBalance` payout stop being used for flag-on orders; money
    flows into the Postgres wallet instead. The release flip must ship together
    with (or immediately before) the wallet UI flip (§5 items 8, 11, §6.3) so
    sellers can see and withdraw their earnings.
14. Withdrawal destination phone is now captured and audited: `Withdrawal`
    gained `phoneNumber` (`withdrawals.phone_number`,

    schema.prisma); `requestWithdrawal` persists the phone submitted in the
    request; `processWithdrawal` pays to the stored phone via the exported
    `withdrawalPayoutPhone(withdrawal)` helper (falls back to the seller profile
    phone for rows created before the column existed; tested). Client: seller
    earnings service + dashboard balance card + home-widget balance read the
    Postgres wallet behind `kUseWalletApi`; withdrawal history maps the v1 status
    set (pending/processing/completed) onto the legacy tile contract.
    DEPLOY NOTE: `prisma db push`/migrate must apply the new column before
    `kUseWalletApi` is flipped — `GET /api/v1/wallet/withdrawals` selects it.
15. Legacy-balance cutover migration built (not yet run): a naive wallet flip
    would hide every pre-flip Firestore `sellerBalance` — sellers would see an
    empty wallet with no way to withdraw their old earnings. `scripts/
    migrate-seller-balances.js` folds each seller's Firestore `sellerBalance`
    (+ historical `totalWithdrawn` stat) into their Postgres wallet via
    `wallet-service.creditLegacyBalance` — idempotent per-seller ledger key
    (`LEGACY_BALANCE`, `legacy_balance_<sellerId>`). `pendingEscrow` is NOT
    migrated on purpose: post-flip it settles through v1 `releaseEscrowAndSettle`
    and would double-credit. Skips sellers with no SellerProfile yet (re-run
    after they log in via v1). OPERATIONS: dry-run first, then `--commit` inside
    the cutoff window, then flip `kUseOrdersApi` + `kUseWalletApi` together.
    Payout pipeline verified: `finance.withdrawalProcess` (every 30 min) moves
    PENDING → `processWithdrawal`; admin finalizes via `confirmPayout`
    (`/api/v1/admin/...` route); stuck processing rows alert admins.
16. Order lifecycle wired client-side (quote/dispatch + buyer release) behind
    `kUseOrdersApi`. Quote call-sites (`seller_quote_screen`,
    `seller_dispatch_screen._setShippingCost`,
    `order_detail_screen._submitSellerShippingCost`) route to v1
    `submitShippingQuote(orderId, amount)` (→ SHIPPING_FEE_SUBMITTED); seller
    dispatch on `order_detail_screen` routes to `dispatchOrder` like the
    existing quote-carousel wiring; buyer "Nimepokea"/confirm-receipt routes to
    `issueHandoverOtp` because v1 escrow release is OTP-gated — the
    seller/recipient completes with `completeOrder(otp)`, which is what settles
    the Postgres wallet. Cancel stays on legacy `/api/escrow/cancel` — v1
    `cancelOrder` rejects IN_ESCROW+ states (no ClickPesa refund yet), and the
    UI only shows cancel for escrow-held orders. Legacy
    `/api/orders/transition`, `/api/orders/set-shipping-cost`, `/api/escrow/
    dispatch`, `/api/escrow/release` remain the default while the flag is off.
    Dispute stays deferred (§5 item 12).

## 6. Next (Phase B) candidates, in dependency order

1. Products catalog bridge: Firestore → Postgres backfill + client switch.
2. Order lifecycle converge: app orders onto `/api/v1/orders` state machine.
   Done (B/C): Postgres truth → Firestore presentation mirror after every
   money-relevant transition (`legacy-status.js` + `presentation-mirror.js`),
   so app streams follow v2 status. Client lifecycle wiring done behind
   `kUseOrdersApi` (§5 item 16): quote, dispatch, OTP handover + release;
   cancel stays on legacy until v1 adds ClickPesa refund for escrow-held
   orders; dispute stays on legacy (§5 item 12) pending R2 evidence path.
3. Payouts → Postgres with idempotency + audit. Server core already existed
   (`wallet-service` + `/api/v1/wallet`); this session: `ensureWallet` money-safety
   fix on both settle paths, OTP-issue authorization, destination-phone
   persistence + payout fallback, flag-gated client bridge (`kUseWalletApi`)
   incl. seller earnings screen, dashboard balance card, and home-widget balance,
   and the legacy-balance cutover migration + idempotent `creditLegacyBalance`.
   Remaining: OPS runs the migration (§5 item 15), then the coordinated
   release+wallet flip (§5 items 8, 13–15), then legacy `/api/payouts/*`
   retirement.
4. Notifications → Postgres app-facing rows: DONE. Server module
   (`notification-service` + routes at `/api/v1/notifications`), Prisma indexes,
   client `NotificationApiClient` + `kUseNotificationsApi` flag, screen + badge
   wiring (badge, mark-read, mark-all, delete all route through the API in flag
   mode; `markRelatedAsRead` no-ops with a badge refresh because v1 has no
   "mark related" endpoint), dual-use service paths, and auth-rejection + unit
   tests all landed. Push delivery (OneSignal) is unchanged; only the persistent
   in-app inbox migrated. Flag stays false until production cutover.
5. Trust passport → Postgres: DONE (client bridge). The v1 trust module
   (`/api/v1/trust`) already existed; this session added Firebase-UID resolution
   to `trust-passport.js` (accepts both SellerProfile.id and SellerProfile.userId,
   so the app's order-detail sellerId — a Firebase UID — works unchanged),
   built `TrustApiClient` + `kUseTrustApi` flag, and wired `TrustPassportCard`
   to read /api/v1/trust/sellers/:id/passport behind the flag. 4 client unit
   tests + 2 server auth tests. Keep the flag false until product/order backfill
   + verification flows are live, otherwise passports show near-empty metrics.
6. Search → Postgres: DONE (client bridge). The v1 search module
   (`/api/v1/search/products`, `search-service.js` — ILIKE + trigram rank on
   published products with price/category filters, category/sort/pagination)
   already existed. `SearchService.globalSearch` now tries
   `SearchApiClient` (`/api/v1/search/products`, new `kUseSearchApi` flag) first
   and returns the "products" source bucket as a `SearchResponse`; on failure or
   an empty Postgres catalog it falls back to the legacy `/api/search
   /global-search` → Firestore path unchanged. Autocomplete, trending,
   most-rated and record-click still use the legacy endpoints. 5 client unit
   tests. Flag stays false until the product backfill has run, otherwise search
   would return zero Postgres rows while Firestore still holds the catalog.
7. Reviews → Postgres: DONE (module + client bridge). New `Review` Prisma model
   (opaque productId/sellerId/userId refs — legacy Firestore doc ids or UIDs
   that survive both eras — plus rating, comment, images, helpful, likedBy,
   seller reply, verified-purchase flag; indexes on productId+createdAt,
   sellerId, userId+productId). New `/api/v1/reviews` module (`review-service`
   + routes): list by product (paginated), seller summary (avg + star
   distribution), my-review lookup, upsert by (userId, productId), helpful
   toggle, seller reply; delete-by-user intentionally absent (not in the app).
   Client: `ReviewApiClient` + `kUseReviewsApi` flag; `ReviewService` and
   `RatingService` reads/writes route through the API in flag mode (list reads
   become one-shot streams because v1 is HTTP, not realtime), with Firestore as
   the default. Self-review and invalid-rating are rejected server-side.
   7 client unit tests + 4 server auth tests. Flag stays false until the
product backfill has run (reviews reference product ids that only exist in
    Firestore); the stream→poll read trade-off is acceptable inside the frozen
    migration window.
8. KYC → Postgres: DONE (module + client bridge). New `KycApplication` Prisma
   model (one row per user, opaque Firebase UID as `userId` — no FK, so rows
   exist pre-backfill and mirror the embedded `users/{uid}.kyc` doc; status
   workflow `pending`→`approved`/`rejected`/`revoked` + delete; indexes on
   status). New `/api/v1/kyc` module (`kyc-service` + routes): `GET
   /status/:userId` (owner or admin), `POST /submit` (authenticated caller is
   always the subject; upserts back to `pending`, rejects if already approved;
   validation mirrors the legacy compat handler byte-for-byte including the
   idType-label switch that the app's `kyc_id_*` values skip, so behavior is
   preserved), plus an `x-admin-secret` admin router: `GET /admin/applications`
   (status-filtered, paginated), `POST /admin/:userId/review`, `POST
   /admin/:userId/revoke`, `DELETE /admin/:userId`. Decisions fan out best-
   effort: Postgres `Notification` row + OneSignal + Firestore notification,
   Firestore `users/{uid}.kyc` mirror, and `products.sellerKycApproved` re-sync
   so the legacy admin panel and Firestore rules stay consistent while the
   bridge is on. Client: `KycApiClient` + `kUseKycApi` flag; `KycService`
   routes through the API in flag mode with legacy Firestore as the fallback
   (kyc_screen unchanged — the client returns legacy-shaped maps). 5 client
   unit tests + 6 server auth tests. Flag stays false until the users backfill/
   `prisma db push` has created `kyc_applications` in production, otherwise
   status reads would return 'none' while Firestore still holds the existing
   application; the Flutter admin panel is NOT wired here yet (it stays on
   legacy `/api/admin/kyc/*` until it adopts x-admin-secret auth). The legacy
   panel's delete button previously 404'd (no `/api/admin/kyc/delete` existed);
   a compat handler now resets `users/{uid}.kyc` to `status: 'none'`, re-syncs
   `sellerKycApproved: false`, audits `kyc_deleted` and notifies the user —
   mirroring the v1 `DELETE /admin/:userId` semantics.