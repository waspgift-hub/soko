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
   search, share, trust, admin, products, referrals, moderation, reconciliation.
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

## 6. Next (Phase B) candidates, in dependency order

1. Products catalog bridge: Firestore → Postgres backfill + client switch.
2. Order lifecycle converge: app orders onto `/api/v1/orders` state machine.
   Done (B/C): Postgres truth → Firestore presentation mirror after every
   money-relevant transition (`legacy-status.js` + `presentation-mirror.js`),
   so app streams follow v2 status. Dispatch wired (client) behind
   `kUseOrdersApi`; next after wallet/payout converge: quote, complete/cancel/
   dispute off legacy-compat onto `/api/v1/orders`.
3. Payouts → Postgres with idempotency + audit.
4. Notifications → Postgres app-facing rows.