# SOKO VIBE UI/UX MODERNIZATION — PHASE 1 AUDIT & IMPLEMENTATION PLAN
**Date:** 2026-11-05  
**Scope:** Existing Flutter app in `soko_langu/` (do not rewrite; preserve backend/business logic)

## 1. Codebase & UI Inventory

### App shell / architecture
- **Entrypoint:** `lib/main.dart` (Provider + `MaterialApp.router`, `DynamicColorBuilder`, `ThemeManager`).
- **Routing:** `lib/app/router.dart` (GoRouter, ~86 page builders/routes), `lib/app/routes.dart` (route constants, includes v2/admin/social/deep-link aliases).
- **State/auth gate:** `lib/app/app_state.dart`, `lib/screens/auth/auth_gate.dart`, `lib/widgets/bottom_nav_bar.dart` (`MainScreen` shell with lazy `IndexedStack` tabs).
- **Theme system:** `lib/theme/` (`app_themes.dart`, `theme_manager.dart`, `dynamic_scheme.dart`, `app_colors.dart`, `app_dimens.dart`, `app_motion.dart`, `app_typography.dart`, `neumorphic.dart`, `surface_policy.dart`, `design_tokens.dart` facade).
- **Design systems present (overlapping):**
  - `lib/widgets/ds/*` (primary DS components: `DsButton`, `DsCard`, `DsSheet`, `DsTextField`, `one_ui.dart`, loading/empty/skeleton/badges, etc.)
  - `lib/design_system/*` (newer One UI tokens/theme + showcase; **barrel exports reference missing files** — must be fixed before adoption)
  - `lib/ui/*` (v2 screens/tokens/theme; parallel UI layer used by router for `/v2` and some routes)
  - Legacy/shared widgets in `lib/widgets/*` and `lib/widgets/premium_widgets.dart`, `soko_widgets.dart`, etc.

### Screen inventory (lib/screens = 88 Dart files)
- **Auth (10):** `auth_gate`, `login`, `register`, `forgot_password`, `verify_email`, `otp_screen`, `otp_verification`, `mfa_enrollment`, `profile_setup`, `lock_screen`
- **Onboarding (3):** `onboarding`, `account_selection`, `artwork_pack`, `tutorials`
- **Home/marketplace (10):** `home`, `discovery`, `search`, `category`, `category_products`, `product_detail`, `product_reviews`, `checkout`, `add_product`, `flash_sale`
- **Chat (6):** `chat_inbox`, `chats_list`, `chat_page`, `chat_navigation`, `create_group`, `group_chat`
- **Profile/social (15):** `profile`, `public_profile`, `settings`, `edit_profile`, `wishlist`, `my_ads`, `seller_dashboard`, `help_center`, `about_app`, `order_flow`, `follower_following`, `follow_requests`, `suggested_accounts`, `blocked_accounts`, `contact_discovery`, `admin_privacy`, `create_flash_sale`
- **Orders/payments/wallet-adjacent (7):** `my_purchases`, `order_detail`, `receipt`, `seller_dispatch`, `seller_orders`, `seller_quote`; seller earnings/analytics under `seller/` (2)
- **Notifications (2):** `notification_screen`, `notification_preferences`
- **Verification/KYC (2):** `kyc_screen`, `verification_center`
- **Boost/requests/report/legal (7):** `boost_product` (+widgets), `buyer_requests`, `post_buyer_request`, `report_screen`, `admin_reports`, `privacy_policy`, `terms_of_service`
- **AI (3):** `ai_assistant`, `ai_settings`, `agent`
- **Admin (9):** dashboard, user detail, KYC + document view, ads config, broadcast, banner management, ClickPesa, transactions tab
- **Company (1):** `company_console`

### V2 UI layer (lib/ui/screens = 8)
`home_v2`, `search_v2`, `product_detail_v2`, `orders_v2`, `profile_v2`, `seller_dashboard_v2`, `chat_v2`, `checkout_v2` (+ `ui/tokens.dart`, `ui/theme.dart`, `ui/widgets/ui_button.dart`). Router exposes v2 routes; coexistence must be preserved.

### Shared components (high impact)
- `lib/widgets/bottom_nav_bar.dart` (main shell tabs, sell FAB, unread badges, desktop sidebar)
- `lib/widgets/product_card.dart`, `banner_rotator`, `product_cached_image`, `soko_*` states/loading/watermark
- `lib/widgets/ds/*` (29 files) and `lib/widgets/ds/one_ui.dart`
- Form/auth widgets: `input_field`, `standard_input_field`, `ds_text_field`, auth scene/widgets

### Backend/business logic areas to protect (no breaking changes)
Firebase Auth/App Check/Crashlytics/Performance, Firestore, `services/*` (follow, chat, notifications, orders, ClickPesa/payments/escrow/wallet/withdrawal as present), repositories/notifiers/providers, models, deep links, ads, analytics, KYC/verification, admin flows. **Do not replace real services with mocks or alter schemas/routes unnecessarily.**

## 2. Key findings (gaps/inconsistencies)
1. **Design system fragmentation:** `theme/*` + `widgets/ds/*` is the live system; `design_system/*` adds parallel One UI tokens/theme but its barrel exports non-existent files (`ds_input`, `ds_list_tile`, `ds_section_header`, `ds_loading`, `ds_toast`, `ds_dialog`, `ds_tab_bar`, `ds_app_bar`, `ds_bottom_nav`, etc.). `widgets/ds/one_ui.dart` is useful but underused.
2. **Color/brand consistency:** App uses Soko Vibe green identity (`#1F8F4E` primary in themes, `#00C853` commerce accents in `SokoColors`) with flat-first + selective soft UI (`Neu`/`SurfacePolicy`). New One UI tokens introduce `#1F8F4E` accent (compatible) but also standalone themes not wired globally—must unify without breaking brand/contrast rules.
3. **Transitions/motion:** `app_transitions.dart` provides global page transitions; should respect `MediaQuery.disableAnimations`/reduced motion and align with `Motion` tokens for a more natural One UI feel.
4. **Main shell nav:** `MainScreen` bottom nav is custom and reasonably modern; can be refined for Samsung-like clarity, accessibility semantics, and reduced-motion safety while preserving tab indices/routes/auth gating/ads hooks.
5. **Dark/light:** ThemeData is centralized and mostly consistent; risk areas are hardcoded colors in screens/widgets (widespread). Full pass requires incremental screen modernization (Phase 7).
6. **Uncommitted work in tree:** Modified profile/follow/auth screens and services, deleted `screens_new`/other dirs in git status. **All modernization changes must avoid touching unrelated modified files unless required and carefully merged.**

## 3. Incremental implementation plan (safe, no destructive rewrite)

### Phase 2 — Unified design system foundation (this pass)
- Fix `lib/design_system/soko_vibe_ds.dart` exports to match existing files (prevent broken imports).
- Enhance `lib/widgets/ds/one_ui.dart` to better express Samsung One UI spacing/radius/motion primitives while **delegating colors to `Theme.of(context).colorScheme`/existing tokens** (preserve Soko Vibe identity; no hardcoded brand overrides that fight `SokoColors`).
- Align `lib/design_system/tokens/one_ui_tokens.dart` and `theme/one_ui_theme.dart` with live brand tokens where used (additive/compatible), without switching global app theme away from `ThemeManager`/`app_themes.dart`.
- Keep `lib/ui/tokens.dart`/`theme.dart` intact for v2 routes.

### Phase 3 — Shared components & shell
- Polish `MainScreen` bottom navigation (visual hierarchy, selection states, badge readability, semantics, reduced-motion support) **without changing tab order, indices, auth gating, or ad callbacks**.
- Improve DS primitives already in use (`DsButton`, `DsCard`, `DsSheet`, `DsTextField`, `one_ui` helpers) for consistency/accessibility where safe.
- Standardize empty/loading/error patterns via existing `ds_*`/`soko_vibe_states` where touched.

### Phase 4 — Navigation & transitions
- Update `lib/app/app_transitions.dart` to respect reduced motion and use smoother, less flashy motion (Samsung-like restraint). Keep GoRouter page builder usage unchanged.

### Phase 5 — Screen modernization (logical groups, incremental)
1. Auth/onboarding: `login`, `register`, `forgot_password`, OTP/verify flows (preserve auth logic).
2. Shell tabs: `home_screen`, `discovery_screen`, `chat_inbox_screen`, `profile_screen` (careful: profile has local modifications).
3. Commerce core: `search_screen`, `category*`, `product_detail`, `add_product`, `checkout`.
4. Social/communication: chat pages, notifications.
5. Account/transactions: settings, wishlist, orders/purchases, receipts, wallet-adjacent seller/order screens.
6. Verification/support/admin: KYC/verification center, help/about/legal, admin dashboard screens.

### Phase 6–8 — Motion, theme consistency, responsive/perf
- Add purposeful micro-interactions via existing `AnimatedPress`/implicit animations; honor `MediaQuery.disableAnimations`.
- Replace hardcoded colors with `colorScheme`/`SokoColors`/DS tokens in touched files.
- Validate responsive behavior with `Responsive` helpers and `LayoutBuilder` on key screens; avoid fixed widths.
- Keep list/image/rendering optimizations (`RepaintBoundary`, lazy loads, cache managers) intact.

### Phase 9 — Verification
- `dart format` on changed files.
- `flutter analyze` (targeted then broader as feasible).
- Run relevant tests if present/fast; smoke-check router/theme compiles.
- **Do not claim rendered visual verification without actual device/emulator inspection.** Report what was statically verified.

## 4. Immediate actions (executed now)
- Create this audit/plan document.
- Fix broken `design_system/soko_vibe_ds.dart` exports.
- Apply safe foundation improvements (OneUI helpers + transitions reduced-motion) to support subsequent screen work.
