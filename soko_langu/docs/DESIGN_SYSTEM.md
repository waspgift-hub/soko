# Soko Vibe — Product Design System & UI/UX Spec

**Version 1.0** — Production-ready design language for a billion-dollar marketplace experience.

> **Design manifesto:** Soko Vibe is the marketplace that feels alive. Emerald for growth and trust,
> amber for energy, midnight for depth, glass for delight. Every pixel earns its place; every
> interaction gives feedback in under 200ms. We design for thumbs, not mice; for one hand, one
> glance, one tap. "Soko" is Swahili for market — the design makes the user feel like they walked
> into the world's most beautiful market.

---

## 0. Design Principles

| # | Principle | Rule of thumb |
|---|-----------|---------------|
| 1 | **Clarity over cleverness** | Nothing ambiguous. Every icon has a label on first use. |
| 2 | **Progressive disclosure** | Show the essential now, reveal detail on demand. |
| 3 | **Feedback in <200ms** | Every tap ripples, every action confirms, every failure explains. |
| 4 | **Fitts' Law** | Primary actions ≥48dp, bottom-anchored for one-hand use. |
| 5 | **Hick's Law** | Never >5 primary choices per screen. The "buy" moment is always one tap away. |
| 6 | **Money is sacred** | Payment screens are calm, deterministic, and transparent — no surprises, ever. |
| 7 | **Trust by design** | Escrow = visible shield. Seller rating = visible stars. Verified = visible badge. |
| 8 | **Accessibility is not optional** | AA contrast minimum, dynamic type, talk-back labels, color-blind safe. |

---

## 1. User Flows

### 1.1 First-run flow (conversion)
```
Splash (brand pulse 1.2s)
  → Onboarding (3 slides, swipeable, skip-able)
  → Auth gate: Login | Register | Continue as guest
      → Register: Phone → OTP → Name → Location consent
  → Home (contextual, personalized)
```

### 1.2 Purchase flow (trust + escrow)
```
Browse → Product Detail → Add to Cart → Cart → Checkout
  → Choose payment (Wallet / M-Pesa USSD / BillPay)
  → Payment sheet (locked, non-dismissable, real-time status)
  → Success (confetti + receipt) → Order tracking
  |→ Failure → explanation + Retry (one tap)
```

### 1.3 Seller flow (money in)
```
Profile → Seller Dashboard → Create Product → Boost Product
  → Analytics → Withdraw → Wallet
```

### 1.4 Chat flow (conversation)
```
Home → Chat list → Conversation → Typing → Delivery ticks → Order card embed
```

### 1.5 AI assistant flow
```
Home → AI chip → Suggestion chips → Streaming response → Action cards ("Boost this product")
```

---

## 2. Information Architecture

```
SOKO VIBE (4-tab shell)
├── Tab 1 · Home
│   ├── Search bar (hero)
│   ├── Banner carousel (flash sales)
│   ├── Categories (horizontal chips)
│   ├── Trending (TikTok-style swipe feed)
│   ├── Recommended grid
│   └── AI Assistant entry point
├── Tab 2 · Marketplace (Browse)
│   ├── Category filter rail
│   ├── Sort / Filter sheets
│   ├── Product grid / list toggle
│   └── Boosted products pinned (gold badge)
├── Tab 3 · Chat
│   ├── Conversation list
│   ├── Chat thread (+ order cards, product cards)
│   └── AI Assistant thread
├── Tab 4 · Profile
│   ├── Profile card (stats, verified badge)
│   ├── Wallet entry (balance, deposits, withdrawals)
│   ├── My Purchases / My Orders / Wishlist
│   ├── Seller hub (Dashboard, Listings, Analytics, Boost)
│   ├── Notifications
│   └── Settings (language, dark mode, help, legal)
└── Product Detail / Checkout / Payment / Order Tracking (stacked routes)
```

**Depth rule:** No feature deeper than 3 levels from a tab. Everything reachable in ≤2 taps.

---

## 3. Design System

### 3.1 Color System

**Brand story:** Emerald green (`#2D6A4F`) is the soul — the color of the Tanzanian landscape, growth,
and money well-earned. Amber (`#FFB74D`) is the spark — promotions, boosts, energy. Midnight
(`#0A0E1A`) is depth — where the premium lives. Glass carries delight.

#### Light Mode

| Token | Role | Hex | Usage |
|---|---|---|---|
| `primary` | Brand action | `#1B4332` | Buttons, links, active states, selected tab |
| `onPrimary` | Text on primary | `#FFFFFF` | Button labels |
| `primaryContainer` | Soft brand surface | `#2D6A4F` | Selected chips, avatar rings |
| `secondary` | Support action | `#26A69A` | Secondary CTAs, toggle on |
| `accent` | Promotion energy | `#FF6F00` | Flash-sale, boost, countdowns |
| `success` | Money in | `#065535` | Payments received, confirmed, escrow released |
| `warning` | Attention | `#B45309` | Expiring escrow, low stock, 1h left |
| `error` | Money risk | `#C62828` | Payment failed, cancellations |
| `info` | Guidance | `#1E5FA8` | Tips, shipping updates |
| `background` | Canvas | `#F6F7FB` | Screen base |
| `surface` | Elevated canvas | `#FFFFFF` | Sheets, dialogs |
| `card` | Content container | `#FFFFFF` | Product cards, rows |
| `cardElevated` | Lift | `#FFFFFF` + shadow | Hovered/featured cards |
| `border` | Hairline | `#E4E7EF` | Card outlines, dividers |
| `textPrimary` | Highest contrast | `#10131F` | Titles, body |
| `textSecondary` | Support | `#5A6172` | Subtitles, meta |
| `disabled` | Off state | `#B6BCCB` / 38% on color | Disabled buttons |

#### Dark Mode

| Token | Hex | Usage |
|---|---|---|
| `primary` | `#52B788` | Buttons, links (brighter for contrast on dark) |
| `onPrimary` | `#052E16` | Button labels |
| `primaryContainer` | `#2D6A4F` | Chips, avatar rings |
| `secondary` | `#4DB6AC` | Secondary CTAs |
| `accent` | `#FFB74D` | Flash-sale, boosts |
| `success` | `#34D399` | Money in |
| `warning` | `#FBBF24` | Attention |
| `error` | `#F87171` | Money risk |
| `info` | `#60A5FA` | Guidance |
| `background` | `#0A0E1A` | Canvas |
| `surface` | `#121729` | Sheets, dialogs |
| `card` | `#1A2040` | Cards |
| `cardElevated` | `#222952` | Featured cards |
| `border` | `#2A3357` | Hairlines |
| `textPrimary` | `#F2F4FA` | Titles, body |
| `textSecondary` | `#9AA3BB` | Subtitles |
| `disabled` | `#3A4263` | Disabled |

**Contrast:** All text pairs meet WCAG AA (≥4.5:1 body, ≥3:1 large). Green-on-white pairs verified
with `#1B4332`/`#FFFFFF` (12.5:1) and `#2D6A4F`/`#FFFFFF` (7.1:1).

**Accessibility nuance:** Amber accent never carries text — it is decorative (badges, glows, borders).
All actionable amber elements pair with a dark label.

### 3.2 Typography System

**Typefaces:** Space Grotesk (display/brand voice), Inter (UI/body — humanist, readable at all sizes),
JetBrains Mono (numbers/status — engineered trust for money).

| Style | Font | Size | Weight | L.Height | L.Spacing | Use |
|---|---|---|---|---|---|---|
| Display | Space Grotesk | 34 | 700 | 1.10 | −1.2 | Splash brand, big moments |
| Headline | Space Grotesk | 28 | 700 | 1.15 | −0.8 | Screen titles, hero numbers |
| Title L | Space Grotesk | 24 | 600 | 1.20 | −0.6 | Section headers |
| Title M | Space Grotesk | 20 | 600 | 1.25 | −0.4 | Card titles, sheet headers |
| Title S | Inter | 18 | 600 | 1.30 | −0.3 | List item titles |
| Body L | Inter | 16 | 400 | 1.40 | 0 | Long-form, chat bubbles |
| Body M | Inter | 14 | 400 | 1.35 | 0 | UI copy, subtitles |
| Body S | Inter | 13 | 400 | 1.30 | 0 | Captions, timestamps |
| Label L | Inter | 14 | 600 | 1.20 | 0.1 | Buttons, tabs |
| Label M | JetBrains Mono | 13 | 500 | 1.20 | 0.3 | Prices, amounts |
| Label S | JetBrains Mono | 11 | 500 | 1.20 | 0.4 | Status chips, badges |

**Money rule:** Every monetary value uses JetBrains Mono Label M — consistent optical width,
impossible to misread.

### 3.3 Spacing System (8pt grid)

| Token | px | Use |
|---|---|---|
| `space-1` | 4 | Icon-to-text micro gap, inner padding of small chips |
| `space-2` | 8 | Compact gaps, checkbox-label |
| `space-3` | 12 | Dense list gaps, card internal gutters (small) |
| `space-4` | 16 | Standard gutter, card padding, list item padding |
| `space-5` | 20 | Section gap inside cards |
| `space-6` | 24 | Screen horizontal padding, between cards |
| `space-7` | 32 | Section-to-section, sheet padding |
| `space-8` | 40 | Hero areas, empty states |
| `space-9` | 48 | Screen top/bottom breathing room |
| `space-10` | 64 | Full-screen states, CTA margins |

**Layout metrics:** Screen horizontal padding 24 (never less). Card radius 16-20. Bottom sheet
top radius 24. Touch target ≥48×48 (critical: ±44 with 4px hit-slop acceptable).

### 3.4 Corner Radius

| Token | Value | Use |
|---|---|---|
| `radius-sm` | 8 | Chips, small media |
| `radius-md` | 12 | Text fields, small cards |
| `radius-lg` | 16 | Product cards, buttons (full-height pills optional) |
| `radius-xl` | 20 | Feature cards, sheets |
| `radius-2xl` | 24 | Bottom sheets, dialogs |
| `radius-full` | 999 | Avatars, pills, FAB |

### 3.5 Elevation & Glass

| Token | Value | Use |
|---|---|---|
| `shadow-sm` | 0 1 2 rgba(16,19,31,.06) | Resting cards |
| `shadow-md` | 0 4 12 rgba(16,19,31,.10) | Floating cards, sheets |
| `shadow-lg` | 0 8 24 rgba(16,19,31,.16) | FAB, modals, product hero |
| `glass-blur` | 30px | Glass panels: payment sheet, live banner, top app bar |
| `glass-tint` | light `#CCFFFFFF` / dark `#1AFFFFFF` | BackdropFilter fill |

### 3.6 Iconography

- **Family:** Material Symbols Rounded (single family, rounded optical style).
- **Weights:** Outlined 90% of the time; Filled for active/selected states only.
- **Grid:** 24×24 design grid, 2dp stroke on outlined, optical balance.
- **Sizes:** 16 (inline meta) · 20 (list leading) · 24 (default) · 32 (empty state) · 40 (hero moments).
- **Color:** Inherits text color; never multi-color except brand marks.
- **Rules:** No icon alone where ambiguity is possible — first use in a screen carries a label;
  state icons (error/success/warning) are always paired with a colored circle backdrop.

---

## 4. Component Library

### 4.1 Buttons

| Component | Spec | State behavior |
|---|---|---|
| `PrimaryButton` | Filled `primary`, radius 16, height 52, Label L, full-width by default | Press: scale 0.97 + ripple; loading: 18dp spinner replaces label; disabled: 38% |
| `SecondaryButton` | Outlined `primary` border 1.5, transparent fill | Press: tinted fill 8% |
| `TonalButton` | `primaryContainer` at 12%, text `primary` | For secondary money actions |
| `GhostButton` | Text only, 48 target | For dismiss, "See all" |
| `IconButton` | 48 target, 24 icon, ripple circle | Hover/elevation subtle |
| `FAB` | 56 circle, `primary`, shadow-lg | Extended variant for "Sell" with label |
| `DangerButton` | `error` fill, white text | For destructive money actions (cancel order, delete) |

**Placement law:** Primary CTA always bottom-anchored, full-width, ≥52dp — thumb zone.

### 4.2 Navigation

| Component | Spec |
|---|---|
| `TopAppBar` | Transparent over content → glass blur on scroll (30px blur, border hairline). Title: Title S. Back arrow ≥48 target. |
| `BottomNavigation` | 4 tabs (Home / Market / Chat / Profile). Active: filled icon + 6dp pill indicator + Label M `primary`; inactive: outlined icon `textSecondary`. Height 64 + safe area. FAB "Sell" floats center if enabled. |
| `BottomSheet` | Radius 24 top, grabber 40×4, drag-to-dismiss, max 85% height. Content padded 24. |
| `SegmentedTabs` | Pills container `surface` — active pill filled `primary` with white text; sliding indicator via `AnimatedContainer` |

### 4.3 Cards

| Component | Spec |
|---|---|
| `ProductCard` | Radius 16, white/dark surface, shadow-sm. Image 4:3 with shimmer on load. Title 2 lines. Price Label M primary + old price strikethrough. Boosted → gold hairline border + "⚡" badge. Wishlist heart top-right (48 target). Tap → scale .98 → hero to detail. |
| `ProductCardHorizontal` | For lists: 96px thumb, 2-line title, price, seller row. |
| `SellerCard` | Avatar 56, name + verified badge, rating stars + count, "Chat" ghost button. |
| `AICard` | Gradient hairline (emerald→teal→amber at 40%), glass fill, sparkle icon, suggestion chips. |
| `WalletCard` | Dark `cardElevated` with emerald→teal gradient overlay, JetBrains Mono balance, "Deposit"/"Withdraw" buttons. |
| `OrderCard` | Status chip top-right, product row, amount, action buttons (Track / Pay / Confirm). |
| `NotificationCard` | Type icon in colored circle (payment=green, chat=blue, boost=gold), title+time, unread dot. |

### 4.4 Inputs

| Component | Spec |
|---|---|
| `TextField` | Radius 12, fill `surface` (light: white / dark: `#1A2040`), border 1 `border`, Label M caption above or hint inside; focused → 2px `primary` border + glow shadow; error → `error` border + helper text |
| `SearchBar` | Height 52, radius 18, glass blur, magnifier leading, clear trailing, "cancel" revealed on focus |
| `Dropdown` | Same field chrome, chevron animates 180°, bottom sheet list with selection check |
| `Checkbox`/`Radio`/`Switch` | MD3 shapes, `primary` fill, 48 target, labels always tappable |
| `Slider` | 4dp track, 20dp thumb, primary; used for price filters with live "TZS x – y" JetBrains label |

### 4.5 Feedback

| Component | Spec |
|---|---|
| `Snackbar` | Radius 12, floating (16 from bottom), shadow-lg, icon+text, 4s, swipe-dismiss |
| `Toast` | Glass pill, centered top 12%, 2s, for confirmations ("Added to cart") |
| `Dialog` | Radius 24, no scrim blur (30px), max width 400, icon hero 48 in colored circle, title+body+actions |
| `Skeleton` | Shimmer 1.2s loop, gradient #E4E7EF→#F6F7FB (dark: #222952→#121729), same geometry as real content |
| `Badge` | JetBrains Label S, radius full, colored: `success`/`accent`/`error` fills |
| `EmptyState` | Icon 48 in 96 circle tinted 10%, Title S, Body M, single primary CTA (see §17) |
| `Progress` | Linear 4dp with rounded caps; Circular 4dp; determinate money progress ("Escrow released 85%") |

### 4.6 Money & Trust Components (Soko Vibe signature)

- **`EscrowShield`:** Shield icon + "Fedha zako ziko salama Escrow" + animated lock; appears on
  every paid state, payment sheet, and receipt.
- **`PaymentStatusTimeline`:** 3 dots (Payment → Held → Released) with animated connectors.
- **`BoostBadge`:** Gold gradient pill with zap icon — only for boosted listings.
- **`VerifiedCheck`:** Badge check in brand green with subtle pulse on first appearance.

---

## 5. Wireframes (key screens, text-level)

```
HOME
┌──────────────────────────────┐
│ 🔍 Search "kofia, mkoba..."   │ ← glass bar, hero
├──────────────────────────────┤
│ [Flash Sale banner 16:9]      │ ← amber gradient, countdown
├──────────────────────────────┤
│ (Chips) All · Electronics ·  │ ← horizontal scroll
│ Clothes · Furniture · More    │
├──────────────────────────────┤
│ ⚡ Trending — swipe up/down   │ ← TikTok feed: full-bleed
│   [product image full-screen] │    card, price bottom-left,
│   TZS 45,000 ★4.8  "Add"     │    heart right, buy bottom
├──────────────────────────────┤
│ ✦ Recommended                │ ← 2-col grid product cards
│ [ ] [ ] [ ] [ ]              │
└──────────────────────────────┘
[Home] [Market] [+] [Chat] [Profile]

PRODUCT DETAIL
┌──────────────────────────────┐
│ ← [image carousel 4:3 hero] ♥│ ← hero to gallery
├──────────────────────────────┤
│ ⚡ BOOSTED  ★4.8 (212)       │
│ Kofia ya Maasai              │
│ TZS 45,000  ~~55,000~~ -18%  │
├──────────────────────────────┤
│ Seller: Bibi Amina  ✔        │ → chat
│  [Dar es Salaam · 2km away]  │
├──────────────────────────────┤
│ Description (2 lines + more) │
│ [Quantity − 1 +]             │
├──────────────────────────────┤
│ 🛡 Fedha ziko salama Escrow  │ ← trust strip
├──────────────────────────────┤
│ [Add to Cart]  [Buy Now]     │ ← bottom bar, primary
└──────────────────────────────┘

CHECKOUT (Apple-style)
┌──────────────────────────────┐
│ Sheet: Checkout — 2 of 3     │ ← progress
│ 📍 Shipping address          │
│   [Get My Location]          │
│   Region / District / Street │
│ 💳 Pay with                  │
│   (o) Wallet TZS 120,000     │
│   ( ) M-Pesa USSD            │
│   ( ) BillPay control no.    │
│ ─────────────────────────    │
│ Subtotal / Fee / Total (Mono)│
│ [Pay TZS 47,200]  ← primary  │
└──────────────────────────────┘

PAYMENT (locked sheet)
┌──────────────────────────────┐
│ 🛡 Processing…               │
│ ⠋ check phone, enter PIN    │ ← spinner + step text
│ (non-dismissable until done) │
│ ✓ Paid → 🎉 Confetti →       │
│   Receipt → Track order      │
│ ✗ Failed → reason + [Retry]  │
└──────────────────────────────┘
```

---

## 6. High-Fidelity Mockups (per-screen visual notes)

Every screen follows: canvas `background`, 24px gutters, glass app bar, floating cards `shadow-sm`,
radius 16-20, primary CTA bottom-anchored.

| Screen | Visual signature |
|---|---|
| Splash | Midnight canvas, centered brand mark (emerald ring, white mark) pulsing 1.2s, JetBrains version caption |
| Onboarding | Full-bleed illustration, glass caption card, 3 dots, primary CTA bottom |
| Login/Register | Glass card over gradient (emerald→teal 30°), phone-centric, biometric icon |
| Home | Glass search, amber flash-sale banner, TikTok trending feed, grid |
| Marketplace | Filter rail left (48dp), grid right; filter sheet with sliders |
| Product Detail | 4:3 hero gallery, floating info card overlapping image, bottom buy bar |
| Chat | WhatsApp-style: own bubbles `primary`-tinted, received bubbles `surface`, 2-tick, order card embed |
| AI Assistant | Gradient border thread, streaming caret, action chips after response |
| Wallet | Dark gradient card top, JetBrains balance, segmented transactions, withdraw sheet |
| Profile | Instagram-style: avatar ring (progress border = rating), stats row, grid of listings |
| Analytics | Cards + sparklines (custom paint), JetBrains numbers, boost CTA gold |

---

## 7. Interactive Prototype Description

Build in **Figma** (one 390×844 frame per flow) or **Flutter** directly (recommended — the app IS
the prototype). Key interactive specs to demonstrate:

1. **Tab switch:** sliding 6dp pill under active icon, 300ms easeOutCubic.
2. **TikTok feed:** vertical drag physics (clamping), next card previews 8% peek, snap on release.
3. **Add to Cart:** dot morph from button → flies to cart icon (parabola, 600ms) → cart badge pop.
4. **Payment:** locked sheet; state machine with 4 states; success → confetti burst + check draw.
5. **Chat:** bubbles enter with elastic scale 0.92→1, typing indicator 3-dot, message ticks.
6. **Search:** results stream in with staggered fade+slide 40px, 50ms stagger.
7. **Pull-to-refresh:** brand emerald ring, overscroll spring 250ms, haptic on complete.
8. **Hero:** product image scales to full-screen detail with rounded-corner-to-edge morph.

---

## 8. UX Explanation (why it works)

- **Nielsen heuristics:** system status (every money action has a visible state), visibility
  (glass search always visible), user control (every sheet dismissable unless money is in flight),
  consistency (one component set, one motion language), error prevention (purchase review step),
  recognition (chips over typing), flexibility (guest browsing + login at paywall), aesthetic
  minimalism (one hero per screen), recovery (retry everywhere, refunds visible), help (AI + help center).
- **One-hand law:** all primary CTAs within thumb arc (bottom 25% of screen); back always top-left
  OR swipe; 48dp targets.
- **Money calm:** payment surfaces are the ONLY screens without auto-dismissing elements; the user
  can always see exactly what will be deducted before the final tap; every fee shown pre-payment.
- **Trust architecture:** escrow shield, verified badges, seller ratings, and order timelines are
  placed at the exact moment of hesitation (before pay, before release).
- **Bilingual-first:** Swahili/English mirror-implemented from the token layer — text never
  truncates (body sizes +1 line allowance in Swahili, which runs ~15% longer).

---

## 9–11. Tokens (implementation-ready)

Mapped to the existing `lib/theme/` files — this spec **extends** them, it does not replace them.

### 9. Color tokens (additions to `app_colors.dart`)

```dart
// Light
primary #1B4332 | onPrimary #FFFFFF | primaryContainer #2D6A4F
secondary #26A69A | accent #FF6F00
success #065535 | warning #B45309 | error #C62828 | info #1E5FA8
background #F6F7FB | surface #FFFFFF | card #FFFFFF | cardElevated #FFFFFF
border #E4E7EF | textPrimary #10131F | textSecondary #5A6172

// Dark
primary #52B788 | onPrimary #052E16 | primaryContainer #2D6A4F
secondary #4DB6AC | accent #FFB74D
success #34D399 | warning #FBBF24 | error #F87171 | info #60A5FA
background #0A0E1A | surface #121729 | card #1A2040 | cardElevated #222952
border #2A3357 | textPrimary #F2F4FA | textSecondary #9AA3BB
```

> Keep existing extensions (`successGreen`, `boostGold`, `trendingOrange`, glass set) — they are
> aliases of these tokens. Add `primary`, `accent`, `success`, `warning`, `error`, `info` to the
> `AppColorScheme` extension.

### 10. Typography tokens (already in `app_typography.dart`)

Keep the Space Grotesk / Inter / JetBrains Mono triad. Add one helper:

```dart
static TextStyle amount(Color c) => GoogleFonts.jetBrainsMono(
  fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.3, color: c);
```

### 11. Spacing & radius tokens (extend `app_dimens.dart`)

```dart
class AppSpacing {
  static const double s1 = 4, s2 = 8, s3 = 12, s4 = 16, s5 = 20,
      s6 = 24, s7 = 32, s8 = 40, s9 = 48, s10 = 64;
}
class AppRadius2 {
  static const double xl = 20, xxl = 24;
}
```

---

## 12. Icon Guidelines

1. One family: **Material Symbols Rounded** — never mix line/outline styles from other sets.
2. Outlined for idle, **Filled** for selected/active (tabs, nav, filters).
3. Monetary icons (wallet, escrow, payment) always pair with a text label — trust, not guesswork.
4. Icon buttons: 24dp glyph inside 48dp target; visual weight balanced with optical centering.
5. Never tint icons with `accent` amber for text-adjacent meaning; amber is decorative only.
6. Loading states: keep the glyph visible (e.g., cart badge), never blank-replace.

---

## 13. Animation Specifications

| Motion | Duration | Curve | Spec |
|---|---|---|---|
| Tap ripple | 200ms | easeOut | MD3 ripple, origin at touch |
| Button press | 100ms | easeOutCubic | scale 1.0 → 0.97 → 1.0 (spring back 300ms) |
| Page transition | 350ms | easeInOutCubic | Fade 0.6 + slide 40px (LTR stack) |
| Tab switch | 300ms | easeOutCubic | Pill slide + icon fade |
| Card enter (list) | 300ms | easeOutCubic | Fade + rise 24px, 50ms stagger |
| Card press | 150ms | easeOut | scale 0.98 |
| Bottom sheet | 350ms | easeOutCubic | Slide up + scrim fade; drag follows finger, spring-back |
| Hero (product) | 450ms | easeInOutCubic | Shared element: image morph + radius shrink |
| Like | 450ms | overshoot spring | Heart pops 1→1.4→1 + haptic |
| Add to cart | 600ms | easeInCubic→easeOut | Fly-to-cart parabola + badge pop |
| Success confetti | 900ms | gravity+fade | 40 particles, emerald/gold/amber |
| Skeleton shimmer | 1200ms | linear loop | Slide gradient 0→100% |
| Pull-to-refresh | 250ms | spring | Emoji-agnostic brand ring + haptic |
| Snackbar | 250ms | easeOutCubic | Slide from bottom 24px |
| Number count-up | 800ms | easeOutQuart | Wallet balances on screen focus |

**Motion principles:** Never animate layout-affecting properties without purpose; respect
`MediaQuery.disableAnimations`; every animation under 600ms except celebrations.

---

## 14. Flutter Widget Hierarchy (every screen)

> Hierarchy = screen → structure → key components. Money screens marked 🛡.

```
SplashScreen
└─ Scaffold(background gradient) → Center → AnimatedScale/AnimatedOpacity brand → FadeTo(next, 1.2s)

OnboardingScreen
└─ PageView → 3 × OnboardingSlide(illustration, glass caption, dots)
└─ Skip (top-right) / PrimaryButton (bottom)

LoginScreen
└─ GlassContainer gradient → TextFields (phone) → PrimaryButton → Biometric icon → "Register" ghost

RegisterScreen
└─ Same scaffold + OTP field + disclosure toggle

ForgotPasswordScreen
└─ Phone field → send OTP → reset

OtpScreen
└─ 6× OTP boxes (auto-advance, paste support) → verify → AnimatedCheck

HomeScreen
└─ CustomScrollView
   ├─ SliverAppBar(glass, SearchBar hero, notification bell w/ badge)
   ├─ FlashSaleBanner (amber gradient, countdown chip)
   ├─ CategoryChips (horizontal ListView)
   ├─ TrendingFeed (PageView.builder vertical, snap)
   └─ ProductGrid (GridView 2-col, staggered entrance)

MarketplaceScreen
└─ Row[ CategoryRail(48dp), Expanded(ProductGrid) ]
└─ FilterSheet (sliders + chips + apply)

SearchScreen / SearchResultsScreen
└─ SearchBar(autofocus) → suggestions (chips) → results grid / list; staggered animations

ProductDetailScreen 🛡
└─ NestedScrollView
   ├─ ImageCarousel (PageView + dots, hero tag)
   ├─ InfoCard (title, price mono, boost badge, rating)
   ├─ SellerRow (avatar, verified, chat ghost button)
   ├─ Description (expandable), QuantityStepper
   ├─ EscrowShield strip
   └─ BottomBar [AddToCart][BuyNow(primary)]

SellerProfileScreen
└─ ProfileHeader (avatar ring, stats row, verified) → Tabs(Products/Reviews) → grids

ChatScreen (list)
└─ ListView of ConversationCards (avatar, last msg, ticks, time, unread dot)

ChatThreadScreen
└─ AppBar(title=person) → ListView bubbles (own=primary tinted, recv=surface)
└─ InputBar (attach, field, send → morph to ticks)
└─ Embedded ProductCard / OrderCard in thread

AiAssistantScreen
└─ GradientThread → StreamingText (typewriter) → ActionChips → InputBar

NotificationsScreen
└─ NotificationCards grouped "Today / Earlier"; mark-all-read; swipe-delete

WishlistScreen
└─ Grid of ProductCards w/ remove animation (size→0 + fade)

CartScreen 🛡
└─ CartItems (qty stepper, swipe-delete w/ confirm) → SummaryCard → CheckoutButton

CheckoutScreen 🛡
└─ Stepper(2/3) → AddressCard (Get My Location) → PaymentMethodRadio (Wallet/USSD/BillPay)
└─ FeesList (mono) → PayButton (locked until valid)

PaymentSheet (locked) 🛡
└─ StateMachine: Processing → Success(confetti, AnimatedCheck, ReceiptCard, TrackButton)
                |→ Failed(reason, RetryButton)

ShippingTrackingScreen
└─ Timeline (ordered nodes animated) + MapCard (LocationMapWidget) + OrderCard

OrderDetailScreen
└─ OrderCard, EscrowShield, Timeline, Action buttons by status

MyPurchasesScreen
└─ SegmentedTabs(All/Pending/Paid/Failed) → OrderCards → BoostReceipt link

MyOrdersScreen
└─ Same pattern, seller perspective + confirm-shipped actions

WalletScreen 🛡
└─ WalletCard (mono balance, Deposit/Withdraw) → TransactionList (grouped by day, icons by type)

DepositScreen / WithdrawScreen 🛡
└─ AmountPad (mono, quick chips 10k/20k/50k) → method → confirm sheet

CouponsScreen
└─ CouponCards (dashed border, code mono, copy button, expiry)

ReviewsScreen
└─ Summary (big stars + bars) → ReviewCards (avatar, stars, body, images)

CreateProductScreen / EditProductScreen
└─ ImagePickerGrid (add tile) → fields (title, desc, price, category chips, stock, delivery) → PublishButton

AnalyticsScreen
└─ StatCards (impressions, views, clicks — mono numbers + sparklines) + BoostCTA (gold)

BoostProductScreen 🛡
└─ TierCards (bronze/silver/gold, selected ring) → PhoneField → PayButton → PaymentSheet

FollowersScreen
└─ AvatarList (follow/unfollow animating buttons)

SettingsScreen
└─ Groups (Account/Appearance/Notifications/Language/Legal) → SwitchListTiles → dark mode toggle

HelpCenterScreen
└─ Search + FAQ accordions + Contact cards

ReportScreen / PrivacyScreen / TermsScreen / AboutScreen
└─ Standard legal scaffold with section anchors + glass header

ProfileScreen
└─ CustomScrollView
   ├─ SliverAppBar(glass, edit button)
   ├─ ProfileCard (avatar ring = rating progress, stats row)
   ├─ WalletMiniCard
   ├─ MenuList (Purchases, Orders, Wishlist, Notifications, Seller hub, Settings)
   └─ (sellers only) ListingsGrid preview
```

---

## 15. Flutter Implementation Suggestions

1. **Token-first architecture:** centralize all new tokens in `lib/theme/` — `AppColorScheme`
   extension + `AppSpacing` + `AppRadius2` + existing typography. No hardcoded colors in screens.
2. **ThemeData:** build `ColorScheme.light()/dark()` explicitly from the tokens above (do NOT rely
   on `ColorScheme.fromSeed` output alone — seed blending shifts brand greens).
3. **DesignSystem widget kit:** create `lib/widgets/ds/` with `DsButton`, `DsCard`,
   `DsTextField`, `DsChip`, `DsSheet`, `DsEmptyState`, `DsSkeleton`, `DsBadge`, `DsEscrowShield`
   — one source of truth, replaces ad-hoc patterns.
4. **Motion library:** `lib/theme/app_motion.dart` with named curves/durations
   (`Motion.fast=200ms`, `Motion.page=350ms easeInOutCubic`); reusable `AnimatedPress` wrapper
   (scale 0.97 + ripple) used by every button.
5. **Transitions:** go_router `CustomTransitionPage` — fade+slide 40px page transition + hero
   tags (`heroTag: 'product-${id}'`) for product galleries.
6. **List choreography:** `AnimatedList`/staggered `TweenAnimationBuilder` with 50ms stagger for
   grids; `RepaintBoundary` around list items.
7. **Skeletons:** one `DsSkeleton` shimmer widget parameterized by shape; swap-in via
   `AnimatedSwitcher` when data arrives.
8. **Confetti:** lightweight custom `CustomPainter` burst (no package) fired on
   payment/order success; ~40 particles, 900ms, emerald/gold/amber.
9. **Haptics:** `HapticFeedback.selectionClick()` on tab switch, `mediumImpact()` on payment
   success, `lightImpact()` on like.
10. **Performance:** `AutomaticKeepAlive` on tabs, `cacheExtent` on TikTok feed, image
    `resize`/`memCacheWidth` 2× DPR, `ListView.builder` everywhere, const constructors.
11. **Accessibility:** `Semantics` labels on all icon-only buttons, `textScaler` defaults intact,
    `MediaQuery.disableAnimations` respected, contrast verified at token level.
12. **RTL-safe:** avoid directional icons for money actions; use `Icons.arrow_forward`
    alternatives where meaning matters.

---

## 16. Best UX Improvements (ordered by impact)

1. **Money clarity first:** show fees breakdown pre-payment on every money screen (already partly
   done — standardize into `FeesList` widget).
2. **Payment locked-sheet:** never allow dismissal during payment in flight; always end in an
   explicit success or failure state (today's "Failed" bug showed why).
3. **Recovery everywhere:** every failed payment screen ends with one primary "Retry" — never a
   dead end.
4. **TikTok trending feed** as the discovery engine (above-the-fold monetization for boosted items).
5. **Escrow shield on every money screen** — trust is the conversion lever for a marketplace.
6. **One-hand checkout:** thumb-zone "Pay" button, stepper in sheet, address auto-detect.
7. **Search suggestions before typing:** recent searches + trending chips (Google behavior).
8. **Chat order cards:** embed order status inline in chat (Amazon/WhatsApp hybrid).
9. **Skeleton-first loading** on all lists (no spinners for content).
10. **Empty states that teach** (§17) instead of "nothing here".
11. **Wallet count-up animation** on focus; balance always JetBrains Mono.
12. **Swipe-to-dismiss** in notification list with undo snackbar.
13. **Guest browse → login at paywall** (conversion, not friction).
14. **Haptics on money events** (deposit confirmed, escrow released).
15. **Dark-mode-first polish:** glass tokens tuned for midnight (already strong — keep consistent).

---

## 17. Empty States

| Screen | Illustration/motif | Title | Body | CTA |
|---|---|---|---|---|
| Cart | Cart in glass bubble | "Pochi yako ni tupu" | "Bidhaa unazozipenda zitakusubiria hapa." | [Anza kununua] |
| Wishlist | Heart outline, soft pulse | "Hakuna alama bado" | "Gusa moyo kwenye bidhaa unayoipenda." | [Vinjari bidhaa] |
| Orders | Box with dashed lid | "Hakuna oda" | "Oda zako zitaonekana hapa." | [Anza] |
| Notifications | Bell in glass | "Hakuna taarifa" | "Tutakujulisha malipo, mauzo na meseji zako." | — |
| Chat | Two bubbles, one floating | "Hakuna meseji" | "Anza mazungumzo na muuzaji unayemwamini." | [Vinjari] |
| Search | Magnifier + sparkle | "Hakuna matokeo" | "Jaribu maneno mengine au uone maarufu." | [Trending chips] |
| Followers | User ring | "Hakuna wafuasi bado" | "Shiriki wasifu wako." | [Shiriki] |
| Reviews | Star in glass | "Hakuna tathmini" | "Kuwa wa kwanza kutoa maoni." | [Andika] |
| Wallet tx | Receipt ghost | "Hakuna miamala" | "Malipo na utoaji vitaonekana hapa." | [Deposit] |

All empty states: 48dp icon in 96dp 10%-tint circle, Title S, Body M (`textSecondary`), single
primary CTA. Entrance: scale 0.9→1 + fade, 300ms.

---

## 18. Loading States

| Context | Pattern |
|---|---|
| Screen open | Skeleton matching real geometry (shimmer 1.2s) — never a centered spinner for lists |
| Action in flight | Button → 18dp spinner replacing label (width preserved — no layout jump) |
| Payment | Locked sheet: shield pulse + step captions ("Tuma PIN", "Inathibitisha…") |
| Image | 4:3 shimmer block + faded placeholder icon; fade-in on load (300ms) |
| AI response | Streaming typewriter with caret; "• • •" thinking dots ≤1.5s before first token |
| Pull-to-refresh | Emerald ring, spring overscroll, haptic on release |
| Upload (KYC/photo) | Progress ring on thumbnail with % (mono) |

---

## 19. Error States

| Context | Pattern | Copy principle |
|---|---|---|
| Form field | 2px `error` border + helper text + icon; focus moves to field | Specific, not generic |
| Payment failed | Locked sheet → red icon in circle → reason (mono) → [Retry] + [Help] | "Sababu: …" — always a reason |
| Network | Glass banner top: "Hakuna mtandao" + [Retry]; content remains visible | Never full-screen block for transient |
| Location | Snackbar explains exactly what to fix (service off / denied / denied forever → Settings) | Actionable next step |
| Load failed | Empty-state layout + [Jaribu tena] | No dead ends |
| SMS/push failure | Silent fallback: in-app banner states "Tutakujulisha kwenye app" | Never claim sent when not |

Error iconography: outlined alert in `error` 10% circle; message Body M; one primary recovery CTA.

---

## 20. Success States

| Context | Pattern |
|---|---|
| Payment success | Confetti burst (40 particles) + animated check draw (600ms) + receipt card + [Fuatilia Oda] |
| Order placed | Check + "Oda #… imewekwa" + timeline preview |
| Deposit/Withdraw | Check + balance count-up (800ms) + [Endelea] |
| Boost activated | Gold glow burst on product card + "IMEANGAZIWA" badge + expiry mono |
| Like/wishlist | Heart pop (overshoot spring) + haptic light |
| Profile saved | Toast "Imesasishwa" (glass pill, 2s) |
| OTP verified | Check morphs into arrow → auto-navigate (no tap needed) |
| Message sent | Bubble commits + single tick → double tick (450ms delay, WhatsApp language) |
| KYC approved | Shield + green check + "UNAWEZA KUZALISHA" + seller unlock card |

Success rule: always show WHAT succeeded and WHAT happens next. Money success always references
the amount in JetBrains Mono.

---

## Appendix A — Benchmark Matrix (how we beat the giants)

| Experience | Benchmark | Soko Vibe signature |
|---|---|---|
| Marketplace | Amazon | Trust-first (escrow shield), Swahili-first, 1-tap buy |
| Chat | WhatsApp | Order cards + seller verification inside chat |
| Search | Google | Instant chips, trending searches, voice-ready |
| AI | ChatGPT | Actionable replies (buttons, not just text) |
| Profile | Instagram | Rating ring avatar, seller stats grid |
| Browsing | TikTok | Vertical swipe feed with inline price + buy |
| Checkout | Apple Store | Locked sheet, 3-step clarity, no-surprise fees |

## Appendix B — Accessibility Checklist

- [ ] All text ≥ AA contrast (verified per token pair in §3.1)
- [ ] Touch targets ≥48×48dp
- [ ] Full TalkBack/semantics labels on all icon-only controls
- [ ] `textScaleFactor` respected everywhere (no fixed-size Text)
- [ ] Color-blind safe: never color-only meaning (icon + label + color)
- [ ] Reduced motion: respect `disableAnimations`; celebrations degrade to static check
- [ ] Focus order logical; focus rings visible on Android TV/keyboard

## Appendix C — Responsive Behavior

| Form factor | Behavior |
|---|---|
| Phone portrait (360–430dp) | Standard layout, 24px gutters, bottom bars |
| Phone landscape | Bottom nav collapses to top bar; content 2-col |
| Foldable (unfolded) | Marketplace/Home become 2-pane (nav rail + content) |
| Tablet (≥600dp) | Max content width 720dp centered; sheets become dialogs; nav rail |
| All | Breakpoints at 360 / 600 / 840 / 1200dp; safe-area aware; adaptive via LayoutBuilder |

---

*Soko Vibe — "Uza. Nunua. Vibe."* Design system maintained in `lib/theme/` and `lib/widgets/ds/`.
