# Soko Vibe

Tanzanian marketplace app — buy and sell goods with escrow protection, AI-powered search, and mobile money payments via ClickPesa.

## Stack

| Layer | Technology |
|---|---|
| **Client** | Flutter 3.x / Dart, GoRouter, Provider |
| **Backend** | Node.js / Express on Render |
| **Database** | Cloud Firestore |
| **Auth** | Firebase Auth (phone OTP) |
| **Payments** | ClickPesa (USSD Push, BillPay, Payouts) |
| **Notifications** | OneSignal (push), Firebase Cloud Messaging |
| **Search** | Firestore composite indexes + server-side filtering |
| **AI** | Groq API (product recommendations, chat assistant) |
| **Maps** | Google Maps Flutter + Flutter Map |

## Architecture

```
lib/
├── app/              # GoRouter config, route guards
├── extensions/       # BuildContext helpers (tr, formatPrice)
├── models/           # Firestore data models (Product, Order, etc.)
├── screens/          # Feature-based screen folders
│   ├── admin/
│   ├── ai/
│   ├── auth/         # Login, Register, OTP, ForgotPassword
│   ├── buyer/
│   ├── chat/
│   ├── home/         # HomeScreen, CheckoutScreen, SearchScreen
│   ├── notification/
│   ├── onboarding/
│   ├── orders/       # OrderDetail, MyPurchases, SellerOrders
│   ├── profile/      # ProfileScreen, EditProfile, SellerDashboard
│   └── seller/
├── services/         # API clients, Firebase wrappers, business logic
├── theme/            # Colors, typography, spacing, design tokens
├── utils/            # Validators, rate limiter, phone utils
└── widgets/          # Reusable widgets + ds/ (design system)
    └── ds/           # DsButton, DsCard, DsTextField, DsChip, etc.

server/
├── index.js          # Express server (~8600 lines)
├── clickpesa.js      # ClickPesa API client + fee calculators
├── listener.js       # Firestore listener for real-time events
├── search.js         # Search router
├── cache.js          # Two-tier caching (memory + Redis)
├── routes/
│   └── payouts.js    # Payout route handlers
└── middlewares/
    └── security.js   # Admin secret verification
```

## Getting Started

### Prerequisites

- Flutter SDK ≥3.11
- Android Studio / VS Code
- Node.js ≥18 (for server)
- Firebase project (sokonimoko-8c171-a8d14)

### Setup

```bash
# Clone
git clone https://github.com/waspgift-hub/soko.git
cd soko/soko_langu

# Install Flutter deps
flutter pub get

# Run debug
flutter run

# Build release APK
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk (64MB)
```

### Server Setup

```bash
cd server
npm install

# Required env vars
CLICKPESA_CLIENT_ID=
CLICKPESA_API_KEY=
CLICKPESA_CHECKSUM_KEY=
CLICKPESA_ALLOWED_IPS=        # Comma-separated IPs for webhook whitelist
MALIPOPAY_WEBHOOK_SECRET=
ONE_SIGNAL_APP_ID=
ONE_SIGNAL_REST_API_KEY=
REDIS_URL=                     # Optional, enables Redis caching
CRON_SECRET=                   # For /api/cron/* endpoints
ADMIN_SECRET=                  # For admin API endpoints

node index.js                  # Runs on port 3000
```

## Commands

```bash
# Flutter
flutter pub get                    # Install dependencies
flutter analyze                    # Lint check (0 errors expected)
flutter test                       # Run 138 unit/widget tests
flutter build apk --release        # Build release APK

# Server
node index.js                      # Start Express server
```

## Key Design Decisions

### Phone-first auth
- Tanzania hardcoded: `+255` prefix, no country selector
- OTP expires in 5 minutes (server-enforced)
- Resend cooldown: 45 seconds
- Router redirect: authenticated users on `/login` or `/register` auto-redirect to `/`

### Account tiers
- Stored in `SharedPreferences` key `'account_tier'`
- Values: `'buyer'`, `'seller'`, `'both'` (default)
- `AccountTierService.getTier()`, `.canBuy`, `.canSell`
- Tier-gated: sell tab visibility, Buy Now button, profile actions

### Payment flow
1. Buyer initiates payment → ClickPesa USSD push sent to phone
2. User enters PIN on phone
3. ClickPesa webhook hits `/api/clickpesa/webhook`
4. Server verifies IP + checksum, acquires Redis lock, updates Firestore
5. Client's `RealtimePaymentBanner` picks up Firestore snapshot instantly
6. HTTP polling (3s) as fallback

### Font system
- All fonts self-hosted (no Google Fonts runtime)
- **Inter**: UI/body text (400, 500, 600)
- **Space Grotesk**: Display/brand (600, 700)
- **JetBrains Mono**: Numbers/prices/status (400, 500, 600)
- `google_fonts` dependency removed

### Design system
- Unified token facade: `Ds` class + `DsContext` extension
- Usage: `final cs = context.cs;` → `cs.primary`, `cs.onSurface`, etc.
- Spacing: `AppSpacing.s1` (4px) through `AppSpacing.s10` (64px)
- All colors via `ColorScheme` — no hardcoded hex in screens

## Testing

```bash
flutter test                       # 138 tests, 0 skipped
flutter analyze                    # 0 errors (warnings are pre-existing)
```

### Test structure
```
test/
├── models/          # Product, NotificationItem, WholesaleTier
├── services/        # AccountTierService
├── theme/           # Design tokens
├── utils/           # Validators (comprehensive)
└── widgets/ds/      # DsButton, DsCard, DsTextField, DsBadge, etc.
```

## APK Optimization

| Technique | Impact |
|---|---|
| R8 minification + full mode | −30% Dart code |
| Resource shrinking | −5% unused assets |
| x86/x86_64 native lib exclusion | −30MB |
| Unused asset removal | −1.5MB |
| Tightened proguard rules | Better dead code elimination |

Final: **64MB** (down from 106.5MB)

## Rate Limiting

### Client-side (SharedPreferences)
| Action | Cooldown |
|---|---|
| OTP send | 45s |
| Password reset OTP | 45s |
| Phone OTP (edit profile) | 60s |
| AI chat (Groq) | 30 req/hour |
| Payment submission | 10s |

### Server-side (in-memory sliding window)
| Endpoint | Limit |
|---|---|
| Phone OTP send | 3/15min per phone |
| Email OTP send | 3/15min per email |
| Search | 20/min per IP |
| Payouts | 10/min per IP |
| Payment initiation | 10/min per IP |

## Environment Variables

### Flutter (android/app/google-services.json)
Auto-generated by Firebase CLI. Do not commit.

### Server (Render dashboard)
| Variable | Purpose |
|---|---|
| `CLICKPESA_CLIENT_ID` | ClickPesa API auth |
| `CLICKPESA_API_KEY` | ClickPesa API auth |
| `CLICKPESA_CHECKSUM_KEY` | Webhook signature verification |
| `CLICKPESA_ALLOWED_IPS` | Webhook IP whitelist |
| `MALIPOPAY_WEBHOOK_SECRET` | Malipay callback verification |
| `ONE_SIGNAL_APP_ID` | Push notifications |
| `ONE_SIGNAL_REST_API_KEY` | Push notifications |
| `REDIS_URL` | Caching + idempotency locks |
| `CRON_SECRET` | Cron endpoint auth |
| `ADMIN_SECRET` | Admin API auth |

## Git

```bash
git remote -v                     # https://github.com/waspgift-hub/soko.git
git branch                        # master (main branch)
```

## License

Private — Soko Vibe. All rights reserved.
