# Security Architecture — Soko Vibe

U haijamini mifumo yetu dhidi ya hackers. Hii ndiyo nyaraka rasmi ya usalama ya msimbazote.

---

## 1. Threat Model

| Attacker | Goal | Primary Defenses |
|----------|------|------------------|
| Unauthenticated user | Access private data, impersonate users | Firebase Auth, Firestore rules, CORS origin allowlist |
| Authenticated user (buyer) | Tamper with prices, overdraw escrow, see seller OTP | Server-side price validation, state machine, OTP subcollection ACL |
| Authenticated user (seller) | Brute-force OTP, release escrow without buyer consent, inflate wallet | bcrypt + 3-attempt lockout, Redis distributed lock, Firestore field protection |
| Compromised client | Replay requests, forge webhooks, escalate privileges | Firebase App Check, webhook HMAC + IP whitelist, Firestore write restrictions |
| Bot / scraper | DoS, credential stuffing, payment abuse | 9 independent rate limiters (server) + client cooldowns |
| Insider / compromised admin | Siphon funds, disable fraud alerts | Admin secret in env (not code), audit log, wallet fields client-unwriteable |

---

## 2. Authentication & Session

### 2.1 Firebase Auth (Phone OTP)

| Control | Location | Details |
|---------|----------|---------|
| OTP generation | `server/index.js:1478,1557` | `crypto.randomInt(100000, 1000000)` — CSPRNG, not `Math.random` |
| OTP expiry | `server/index.js:1499,1575` | 5 minutes — server-enforced via `expiresAt` timestamp |
| Rate limit: send OTP | `server/index.js:1361-1407` | 3 per 15 min per phone number |
| Rate limit: verify OTP | `server/index.js:1390-1407` | 5 per 15 min per phone/email |
| Auto-created accounts | `server/index.js:1767` | `crypto.randomBytes(24).toString('base64url')` — 192-bit random password (was deterministic 24-char before audit) |
| Token verification | `server/index.js:854-867` | `admin.auth().verifyIdToken()` on every protected endpoint |
| Session persistence | `main.dart` | Firebase handles token refresh; app stores no plaintext credentials |

### 2.2 Email OTP

| Control | Location | Details |
|---------|----------|---------|
| OTP generation | `server/index.js:1557` | `crypto.randomInt(100000, 1000000)` |
| Rate limit | `server/index.js:1409-1443` | 3 per 15 min per email |
| Transport | `server/index.js:1572-1623` | Nodemailer via Gmail SMTP; credentials in env |

### 2.3 Password Policy

| Control | Location | Details |
|---------|----------|---------|
| Minimum length | `lib/utils/validators.dart:11` | 8 characters (enforced consistently — validator + all auth screens) |
| Strength indicator | `lib/widgets/auth/password_strength_indicator.dart` | Scores 0–4 based on length, mixed case, digits, special chars |
| Reset flow | `lib/screens/auth/forgot_password_screen.dart:142-149` | Client: confirm-match + min 8 chars. Server: Firebase `updatePassword()` |

### 2.4 Firebase App Check

| Control | Location | Details |
|---------|----------|---------|
| Android | `lib/main.dart:476-488` | Play Integrity attestation |
| iOS | `lib/main.dart:476-488` | DeviceCheck attestation |
| Effect | Server | All API requests from non-app clients (curl, scripts) rejected by Firebase enforcement |

### 2.5 Device Security

| Control | Location | Details |
|---------|----------|---------|
| Root/jailbreak detection | `lib/main.dart:500-505` | `SecurityService().initialize()` — blocks rooted devices |
| App lock overlay | `lib/main.dart:614 + 252-276` | Biometric/PIN lock on app resume |
| Crashlytics | `lib/main.dart:131-140` | Top-level error handler — catches unhandled exceptions |

---

## 3. Webhook Security (3-Layer Defense)

### 3.1 ClickPesa Webhook

| Layer | Mechanism | Location |
|-------|-----------|----------|
| **1. IP Whitelist** | CIDR-aware IP check against `CLICKPESA_ALLOWED_IPS` env var; strips `::ffff:` IPv6 prefix; rejects in production when unconfigured | `server/index.js:682-705` |
| **2. HMAC-SHA256** | Canonicalized JSON payload (sorted keys at every nesting level) checksummed with `CLICKPESA_CHECKSUM_KEY`; compared against `body.checksum` | `server/index.js:721-741`, `server/clickpesa.js:25-41` |
| **3. Redis Idempotency** | `SET webhook:<ref> NX EX 3600` — duplicate webhooks silently ignored within 1 hour | `server/index.js:2857+` |

Webhooks are registered **before** the global rate limiter (lines 139, 184, 239) so provider callbacks are never throttled.

### 3.2 Malipopay Webhook

| Layer | Mechanism | Location |
|-------|-----------|----------|
| **1. HMAC-SHA256** | `req.rawBody` hashed with `MALIPOPAY_WEBHOOK_SECRET`; compared against `X-Malipopay-Signature` via `crypto.timingSafeEqual` with length pre-check | `server/index.js:190-237` |
| **2. Duplicate Dedup** | `reference` field checked against Firestore; same reference within 24h silently OK'd | `server/index.js:218-231` |

### 3.3 WhatsApp Webhook

| Layer | Mechanism | Location |
|-------|-----------|----------|
| **1. HMAC-SHA256** | `JSON.stringify(body)` hashed with `WHATSAPP_WEBHOOK_SECRET`; constant-time comparison via `crypto.timingSafeEqual` | `server/index.js:143-181` |
| **2. PDPA Compliance** | Phone numbers masked in all console logs | `server/index.js:167` |

### 3.4 Raw Body Preservation

`express.json()` configured with `verify: (req, _res, buf) => { req.rawBody = buf; }` — preserves exact bytes for HMAC verification. Without this, JSON parsing could alter whitespace/encoding.

---

## 4. Firestore Security Rules (Data-Level Access Control)

### 4.1 Helper Functions

| Function | Purpose | Location |
|----------|---------|----------|
| `isSignedIn()` | Rejects unauthenticated reads/writes | `firestore.rules:5` |
| `isOwner(userId)` | Owner-only access gate | `firestore.rules:9` |
| `isAdmin()` | Reads `users/{uid}.isAdmin` server-side | `firestore.rules:14` |
| `notSuspended()` | Blocks suspended users from write ops | `firestore.rules:21` |
| `noSensitiveFieldChanges()` | **Prevents client writes to**: `walletBalance`, `sellerBalance`, `pendingEscrow`, `totalSales`, `grossSalesVolume`, `totalWithdrawn`, `isAdmin`, `isSuspended`, `kyc`, `isBoosted`, `boostedUntil`, `boostTier` | `firestore.rules:33-44` |
| `noSensitiveCreateFields()` | **Prevents new user docs from bootstrapping financial/trust state** — `sellerBalance` must be 0, `isAdmin`/`isSuspended` must be false | `firestore.rules:53-64` |

### 4.2 Collection-Level Controls

| Collection | Read | Create | Update | Delete | Key Anti-Abuse |
|------------|------|--------|--------|--------|----------------|
| `users/{uid}` | Any signed-in user | Owner + `noSensitiveCreateFields` | Owner + `noSensitiveFieldChanges` OR admin | Owner or admin | **Wallet fields client-unwriteable** |
| `products/{id}` | Public (marketplace browse) | Owner + not suspended | Owner (no boost fields) OR server-only `viewCount`/`soldCount` OR admin | Owner or admin | **Boost fields server-only** |
| `orders/{id}` | Buyer, seller, or admin | Buyer only | Buyer, seller, or admin | Admin only | **Delivery OTP subcollection buyer-only** |
| `orders/{id}/delivery_otp/buyer` | **Buyer only** | Never | Never | Never | **Plaintext OTP: seller cannot read; write locked** |
| `transactions/{id}` | Buyer, seller, or admin | Buyer only | `deletedForBuyer` OR `deletedForSeller`+`shippingCost` OR admin | Admin only | **Status/amount fields server-only** |
| `reviews/{id}` | Public | Owner + not self-review | Like/unlike OR seller reply only | Owner only | **Self-review prevention** |
| `conversations/{id}` | Participants only | Participants only | Participants only | Admin only | **Conversation ID = `{uid1}_{uid2}`** |
| `chat_rooms/{id}` | Participants only | Participants only | Participants only | Admin only | **Room-level + message-level checks** |
| `notifications/{id}` | Owner or admin | Owner + schema validation | **Only `isRead` field** | Owner only | **Field-level write restriction** |
| `payouts/{id}` | Owner or admin | Admin only | Admin only | Admin only | **Server-only** |
| `platform_earnings` | Admin only | Admin only | Admin only | Admin only | **Admin-only** |
| `audit_log` | Admin only | Admin only | Admin only | Admin only | **Immutable audit trail** |

### 4.3 Derived Security Properties

- **Privilege escalation impossible**: A client can never set `isAdmin: true` because `noSensitiveFieldChanges()` blocks it on update, and `noSensitiveCreateFields()` blocks it on create.
- **Wallet tampering impossible**: `walletBalance`, `sellerBalance`, `pendingEscrow`, `totalSales`, `grossSalesVolume`, `totalWithdrawn` are all in the blocked fields list. Only the admin SDK (server) can modify them.
- **Boost fraud impossible**: `isBoosted`, `boostedUntil`, `boostTier` are server-only. A seller cannot self-boost.
- **OTP isolation**: The buyer's plaintext OTP lives in `orders/{id}/delivery_otp/buyer` — the seller's Firestore client SDK physically cannot read this document (rules reject it). The bcrypt hash lives on the parent `orders/{id}` doc, readable by both parties (harmless without the plaintext).

---

## 5. Server-Side Rate Limiting (9 Independent Limiters)

All implemented as in-memory `Map<string, {count, firstHit}>` with automatic bucket sweeping every 5 minutes (prevents OOM on Render's 512MB plan).

| # | Limiter | Window | Max | Key | Location |
|---|---------|--------|-----|-----|----------|
| 1 | `rateLimit()` | 60s | 30 | IP | `server/index.js:531-565` |
| 2 | `paymentRateLimit()` | 60s | 5 | IP | `server/index.js:567-579` |
| 3 | `otpPhoneRateLimit()` | 15 min | 3 | Phone digits | `server/index.js:1361-1388` |
| 4 | `otpVerifyRateLimit()` | 15 min | 5 | Phone/email | `server/index.js:1390-1407` |
| 5 | `otpEmailRateLimit()` | 15 min | 3 | Email (lowercase) | `server/index.js:1409-1443` |
| 6 | `searchRateLimit()` | 60s | 20 | IP | `server/index.js:1441-1465` |
| 7 | `payoutRateLimit()` | 60s | 10 | IP | `server/index.js:1467-1491` |
| 8 | `forgot_password` | 45s cooldown | 1 | Device (SharedPreferences) | `lib/utils/rate_limiter.dart` + `forgot_password_screen.dart:106` |
| 9 | `register_otp` | 45s cooldown | 1 | Device (SharedPreferences) | `lib/utils/rate_limiter.dart` + `register_screen.dart:144` |
| 10 | `pay_order` | 10s cooldown | 1 | Device (SharedPreferences) | `lib/utils/rate_limiter.dart` + `order_detail_screen.dart:2381` |

**Admin bypass**: Requests containing a valid `x-admin-secret` header bypass the general rate limiter (line 553–554) — webhook callbacks from ClickPesa use this path.

**Webhooks exempt**: ClickPesa, Malipopay, and WhatsApp webhook routes are registered **before** the `app.use('/api', rateLimit())` middleware (lines 139, 184, 239) — provider callbacks are never throttled.

---

## 6. Delivery Verification OTP System (Escrow Release)

### 6.1 Flow

```
Seller dispatches → status: 'dispatched'
         ↓
Server generates 4-digit OTP (CSPRNG)
  - Hash stored on orders/{id} doc (bcrypt, 10 rounds)
  - Plaintext stored in orders/{id}/delivery_otp/buyer (Firestore rule: buyer-only)
         ↓
Buyer sees OTP on screen → shares verbally/in-person with seller
         ↓
Seller enters OTP → Server verifies (bcrypt.compare)
         ↓
Redis distributed lock prevents concurrent release
         ↓
ClickPesa payout triggered → status: 'completed'
```

### 6.2 Security Controls

| Control | Mechanism | Location |
|---------|-----------|----------|
| **CSPRNG OTP** | `crypto.randomInt(100000, 1000000)` for 4-digit code | `delivery_otp.js:16` |
| **bcrypt hashing** | 10-round salted bcrypt; plaintext never in hash field | `delivery_otp.js:19-25` |
| **Brute-force lockout** | Max 3 attempts → 24-hour lock persisted to Firestore | `delivery_otp.js:132-139` |
| **Fail-closed counting** | Attempt counter incremented **before** bcrypt comparison | `delivery_otp.js:140-143` |
| **Distributed lock** | Redis `SET delivery:lock:<id> NX EX 30` — prevents race-condition double release | `delivery_otp.js:149-156` |
| **Idempotency guard** | Rejects if `escrowReleased === true` already | `delivery_otp.js:120` |
| **Dispute freeze** | Cannot verify while order is disputed/unresolved | `delivery_otp.js:121` |
| **Seller notification** | OneSignal alert on lockout (3 failed attempts) | `delivery_otp.js:137-139` |
| **OTP isolation** | Buyer reads plaintext via Firestore rule; seller cannot read OTP fields | `firestore.rules:152-157` |
| **48h auto-release cron** | Protected by `CRON_SECRET` header (timingSafeEqual); requires evidence; per-order Redis lock | `delivery_otp.js:326-450` |
| **Audit trail** | `confirmedBy: 'otp'` or `'auto_release_48h'` with `serverTimestamp()` | `delivery_otp.js:163-170, 369-374` |
| **Pending escrow clamp** | `Math.min(sellerReceives, pendingBefore)` prevents negative/over-decrement | `delivery_otp.js:172-176` |

### 6.3 Auto-Release Cron

| Control | Details |
|---------|---------|
| Secret authentication | `x-cron-secret` header vs `CRON_SECRET` env var; `crypto.timingSafeEqual` |
| Time threshold | Only orders dispatched > 48 hours ago |
| Evidence gate | Requires `buyerTransport` or `dispatchProof` before releasing |
| Dispute freeze | Skips orders with unresolved disputes |
| Worker isolation | Per-order Redis lock (`auto-release:lock:<orderId> NX EX 60`) |
| Batch limit | Max 50 orders per invocation |

---

## 7. Order Status Engine (State Machine)

### 7.1 Legal Transitions

```
pending → quoted → awaiting_payment → paid → paid_escrow_hold → escrow_hold
  → dispatched → delivered → confirmed → completed
                                          ↕ disputed → refunded
                          cancelled ←──── any active state
```

Implemented as a **whitelist state machine** — only explicitly listed transitions are allowed. Unknown transitions return `false`.

| Location | Control |
|----------|---------|
| `server/orders.js:36-51` | `isValidTransition(from, to)` — explicit allowed-next-status map |
| `server/orders.js:55-60` | `ROLE_ALLOWED_TRANSITIONS` — **role-based authorization** (seller/buyer/admin/system) |
| `server/orders.js:62-66` | `canActorTransition(role, status)` — deny-by-default for unknown roles |
| `server/orders.js:108-114` | `transitionOrder()` validates before write; throws on illegal transition |
| `server/orders.js:132` | `statusHistory` append with `by: actorId` — immutable audit attribution |

### 7.2 Role-Based Access Matrix

| Actor | Allowed Transitions |
|-------|-------------------|
| **Seller** | `→ quoted`, `→ dispatched`, `→ cancelled` |
| **Buyer** | `→ paid`, `→ disputed`, `→ confirmed`, `→ cancelled` |
| **Admin** | `→ refunded`, `→ completed`, `→ cancelled` |
| **System** | `→ escrow_hold`, `→ failed` |

**Terminal states**: `completed`, `cancelled`, `refunded` — empty transition arrays (immutable once reached).

---

## 8. Server-Side Price Validation

| Control | Location | Details |
|---------|----------|---------|
| Trust boundary | `server/money.js:35-37` | Client-supplied price is **never trusted**; server fetches from `products` doc |
| Flash sale validation | `server/money.js:43-58` | Active flash sale price resolved from `flash_sales` collection, time-gated |
| Product price override | `server/money.js:62-68` | `products/{id}.price` used as source of truth |
| Client fallback only | `server/money.js:72` | Client price used **only** when both server lookups fail (network error) — logged |
| Integer normalization | `server/money.js:56,67,72` | `Math.round(Number(...))` — guards against fractional/negative/NaN |

**Attack scenario prevented**: A user modifies the app to send `price: 1` for a TSh 500,000 product. Server ignores it, fetches the real price, charges correctly.

---

## 9. Input Validation & Sanitization (Client-Side)

### 9.1 Authentication Screens

| Field | Validation | Location |
|-------|-----------|----------|
| Email | Regex `^[^@\s]+@[^@\s]+\.[^@\s]+$` | `forgot_password_screen.dart:45-51` |
| Phone | Strip non-digits, require ≥ 9 digits | `forgot_password_screen.dart:53-58` |
| Phone normalization | E.164-style `255XXXXXXXXX` | `lib/utils/phone_utils.dart:45-50` |
| Password | Min 8 chars + live strength indicator (0–4 score) | `validators.dart:11`, `password_strength_indicator.dart:7-18` |
| OTP input | `FilteringTextInputFormatter.digitsOnly`, maxLength 4/6 | Various OTP screens |

### 9.2 Chat

| Control | Location | Details |
|---------|----------|---------|
| Message length | Hard cap at 2000 characters (TextField `maxLength`) | `chat_page.dart:618-624` |
| Empty/trimming | Rejects empty after trim | `chat_page.dart:174-176` |
| Profanity filter | Local `SafeTextFilter` (Swahili) → server `/api/moderation/check-text` | `profanity_filter.dart:15-38` |
| Fail-closed | Network error → returns `clean: false` (blocks send) | `profanity_filter.dart:40` |
| Auto-signout | Server returns `banned` → `FirebaseAuth.instance.signOut()` | `chat_page.dart:185` |

### 9.3 Checkout

| Field | Validation | Location |
|-------|-----------|----------|
| Phone | `FilteringTextInputFormatter.digitsOnly` + E.164 normalization | `checkout_screen.dart:299, 720` |
| Address | Lowercased, trimmed, suffix-stripped | `checkout_screen.dart:92-128` |

### 9.4 Profile

| Field | Validation | Location |
|-------|-----------|----------|
| Bio | `maxLength: 500`, trimmed before save | `edit_profile_screen.dart:559-568, 383` |
| Username | Required, no spaces, min 3 chars, lowercased | `edit_profile_screen.dart:549-556, 364` |
| Phone change | Trim + digit-strip + min-length gate | `edit_profile_screen.dart:265-272` |

### 9.5 Search

| Control | Location | Details |
|---------|----------|---------|
| Min query length | ≥ 2 characters before suggestions fire | `search_screen.dart:180-188` |
| Debounce | 200ms timer prevents suggestion flooding | `search_screen.dart:180-188` |
| Empty rejection | Trimmed empty query rejected before API call | `search_screen.dart:199-201` |

### 9.6 KYC

| Control | Location | Details |
|---------|----------|---------|
| ID type | Fixed whitelist dropdown (national/passport/drivers/voters) — no free-text | `kyc_screen.dart:33-38` |
| ID number | Digits only + `maxLength: 20` | `kyc_screen.dart:321-324` |
| Image bounds | 1024×1024 max — limits upload payload | `kyc_screen.dart:110` |
| Required fields | Both ID image + selfie + fullName + idNumber required | `kyc_screen.dart:123-141` |

---

## 10. CORS Configuration

| Control | Location | Details |
|---------|----------|---------|
| Origin allowlist | `server/index.js:101-111` | Explicit allowlist: Render, Railway, Firebase hosting, Capacitor, localhost |
| Exact match only | `server/index.js:114-117` | `origin === allowed` — blocks look-alike origins like `onrender.com.evil.com` |
| Methods | `server/index.js:118` | Explicit list (GET, POST, PUT, DELETE, OPTIONS) |
| Credentials | `server/index.js:121` | `credentials: false` — no cookie-based auth leakage |
| Custom headers | `server/index.js:120` | Allows `x-admin-secret`, `x-webhook-secret`, `x-notify-signature`, `x-malipopay-signature` |

---

## 11. Constant-Time Comparisons (Timing Attack Prevention)

All secret/token comparisons use `crypto.timingSafeEqual` to prevent timing-based side-channel attacks:

| Secret | Location |
|--------|----------|
| Admin secret | `server/middlewares/security.js:8-12` |
| WhatsApp HMAC | `server/index.js:160` |
| Malipopay HMAC | `server/index.js:210` |
| Cron secret (delivery OTP) | `server/routes/delivery_otp.js:340` |
| ClickPesa checksum | `server/index.js:721-741` (via `createPayloadChecksum`) |

**Pattern**: Length equality checked first → `Buffer` comparison → `timingSafeEqual`. Fail-closed if either side is empty/missing.

---

## 12. Cryptographic Primitives

| Primitive | Use | Location |
|-----------|-----|----------|
| `crypto.randomInt(min, max)` | OTP generation (phone, email, delivery) | `server/index.js:1478,1557`, `delivery_otp.js:16` |
| `crypto.randomBytes(24)` | Auto-account passwords (192-bit entropy) | `server/index.js:1767` |
| `crypto.createHmac('sha256', key)` | ClickPesa payload checksum, webhook verification | `server/clickpesa.js:34-41`, `server/index.js:721-741` |
| `crypto.timingSafeEqual` | All secret comparisons (5 locations) | See Section 11 |
| `bcryptjs` (10 rounds) | Delivery OTP storage | `delivery_otp.js:19-25` |

**What we never use**: `Math.random()` for any security-sensitive operation (was fixed in audit — H-3).

---

## 13. Android Security

| Control | Location | Details |
|---------|----------|---------|
| `allowBackup="false"` | `AndroidManifest.xml` | Prevents adb backup extraction of app data/credentials |
| `fullBackupContent="false"` | `AndroidManifest.xml` | Disables Android Auto Backup entirely |
| Firebase App Check | `main.dart:476-488` | Play Integrity attestation blocks emulators/scripts |
| Root detection | `main.dart:500-505` | `SecurityService` blocks rooted devices |

---

## 14. Client-Side Rate Limiting

Centralized `RateLimiter` utility backed by `SharedPreferences` timestamps:

| Control | Location |
|---------|----------|
| `canProceed()` cooldown gate | `lib/utils/rate_limiter.dart:8-18` |
| Sliding-window counter | `lib/utils/rate_limiter.dart:31-49` |
| Attempt increment + reset | `lib/utils/rate_limiter.dart:51-60` |

**Limitation**: SharedPreferences-based limits are bypassable by clearing app data. They complement (not replace) server-side and App Check enforcement.

---

## 15. AI (Groq) Security

| Control | Location | Details |
|---------|----------|---------|
| Server proxy | `lib/services/groq_service.dart:11,15` | API key NEVER in Flutter app; all calls go through server proxy |
| Auth required | `lib/services/groq_service.dart:226-228` | Proxy refuses unauthenticated calls; fresh `getIdToken()` per request |
| Rate limit | `lib/services/groq_service.dart:255-258` | Max 30 AI requests per 60 minutes per user |
| Prompt bounds | `lib/services/groq_service.dart:260-262` | Conversation history truncated to last 40 entries |

---

## 16. Router Security (Navigation Guards)

| Control | Location | Details |
|---------|----------|---------|
| Protected routes | `lib/app/router.dart:78-106` | ~25 routes require authentication |
| Admin routes | `lib/app/router.dart:108-114` | 5 admin-only routes |
| Auth redirect | `lib/app/router.dart:121-149` | Unauthenticated → login; authenticated on login/register → home |
| Admin gate | `lib/app/router.dart:138-141` | Admin routes require both auth + admin flag |
| Type guard | `lib/app/router.dart:360-365` | Checkout route validates `extra` is valid `Product` object |

---

## 17. Git Secrets Protection

| Control | Location | Details |
|---------|----------|---------|
| `.gitignore` includes | Root `.gitignore` | `CREDENTIALS.txt`, `*.p12`, `*.jks`, `*.keystore`, `google-services.json`, `GoogleService-Info.plist`, `server.err`, `*.err` |
| Service account JSON | Env var only | `FIREBASE_SERVICE_ACCOUNT_JSON` — never committed |
| All API keys | Env vars only | `CLICKPESA_CLIENT_ID`, `CLICKPESA_API_KEY`, `CLICKPESA_CHECKSUM_KEY`, `ADMIN_SECRET`, `CRON_SECRET`, `MALIPOPAY_WEBHOOK_SECRET`, `WHATSAPP_WEBHOOK_SECRET`, `GMAIL_USER`, `GMAIL_PASS` |

---

## 18. Audit & Monitoring

| Control | Location | Details |
|---------|----------|---------|
| Order timeline | `server/orders.js:78-84,132` | Immutable `statusHistory` entries with `by: actorId` + `serverTimestamp()` |
| Escrow audit log | `delivery_otp.js:183-190` | `auditLog()` records `escrow_release` with userId, amount, orderId |
| Fraud alerts | `firestore.rules:473-478` | `fraud_alerts` collection — admin-only |
| Audit log | `firestore.rules:480-484` | `audit_log` collection — admin-only, immutable |
| Crashlytics | `lib/main.dart:131-140` | Top-level error handler catches all unhandled exceptions |
| Webhook logs | `server/index.js` | `whatsapp_webhook_logs`, `malipay_webhook_logs` — admin-only |

---

## 19. Payment Security (ClickPesa Integration)

| Control | Location | Details |
|---------|----------|---------|
| Gateway fee fetch | Server-side | Fee calculated from ClickPesa API, not client-supplied |
| Idempotent webhooks | Redis lock `webhook:<ref> NX EX 3600` | Prevents double-processing on multi-instance Render |
| Payment reconciliation | Background job | Cross-references ClickPesa API status vs Firestore |
| Status polling (client) | `order_detail_screen.dart` | 3-second interval with lifecycle-safe mounted checks |
| Double-pay prevention | `lib/utils/rate_limiter.dart` | 10-second client cooldown on payment submission |

---

## 20. Memory & Resource Protection

| Control | Location | Details |
|---------|----------|---------|
| Image cache cap | `lib/main.dart:74-76` | 200MB max — prevents OOM on low-RAM devices |
| Rate limiter bucket sweep | `server/index.js:539-548` | Every 5 minutes, prunes expired buckets (prevents OOM on 512MB Render) |
| `otpVerifyHits` sweep | `server/index.js:1405-1420` | Delivery OTP attempt map cleaned every 5 minutes |
| Lifecycle-safe async | Throughout Flutter code | Every async callback checks `if (!mounted) return` before `setState` |
| Subscription disposal | All StatefulWidgets | `StreamSubscription`, `TextEditingController`, `Timer` disposed in `dispose()` |

---

## 21. Known Limitations & Future Hardening

| # | Item | Status |
|---|------|--------|
| 1 | Rate limiter is in-memory (not distributed across Render instances) | Mitigated by App Check + Firebase Auth |
| 2 | Client-side SharedPreferences rate limits bypassable by clearing data | Mitigated by server-side limits |
| 3 | Delivery OTP plaintext in Firestore `orders/{id}/delivery_otp/buyer` | Protected by Firestore rule (buyer-only); consider FCM-only delivery for v2 |
| 4 | `validators.dart` password min length vs screen-level enforcement | Fixed: aligned to 8 chars |
| 5 | No IP-based geo-restriction | Tanzania-only phone numbers (+255) implicit |
| 6 | Render free-tier cold starts may delay webhook processing | Mitigated by webhook idempotency + retry from providers |

---

## 22. Security Audit History

| Date | Finding | Severity | Fix | Status |
|------|---------|----------|-----|--------|
| 2026-08-21 | Deterministic password for auto-created accounts | CRITICAL | `crypto.randomBytes(24)` | Fixed |
| 2026-08-21 | Client-supplied price trusted in payment flow | HIGH | Server-side `resolveEffectivePrice()` | Fixed |
| 2026-08-21 | No rate limit on `/api/phone-login` verify | HIGH | `otpVerifyRateLimit` (5/15min) | Fixed |
| 2026-08-21 | `Math.random()` for OTP generation | HIGH | `crypto.randomInt()` everywhere | Fixed |
| 2026-08-21 | WhatsApp HMAC `!==` comparison | LOW | `crypto.timingSafeEqual` | Fixed |
| 2026-08-21 | Android `allowBackup` enabled | MEDIUM | `allowBackup="false"` + `fullBackupContent="false"` | Fixed |
| 2026-08-21 | `server.err` tracked in git | MEDIUM | Added to `.gitignore` | Fixed |
| 2026-08-21 | Password validator allows 6 chars | MEDIUM | Aligned to 8 chars | Fixed |
| 2026-08-21 | Cron secret uses `!==` comparison | LOW | `crypto.timingSafeEqual` | Fixed |
