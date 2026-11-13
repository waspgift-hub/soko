# SOKO VIBE BANNER ECOSYSTEM — ARCHITECTURE AUDIT (2026-11-05)

## Scope audited
- `lib/widgets/banner_rotator.dart`, `flash_sale_banner.dart`, `ads_promo_banner.dart`, `dynamic_banner.dart`, `payment_banner.dart`
- `lib/models/banner_model.dart`, `lib/services/banner_service.dart`
- `lib/screens/admin/admin_banner_management_screen.dart`
- `lib/screens/home/home_screen.dart`, `lib/screens/home/discovery_screen.dart`

## Current architecture (preserve)
- **Home:** `HomeScreen` subscribes to `FlashSaleService.getActiveFlashSalesMapAtNow` and renders `BannerRotator(flashSales: ...)`. Product cards also receive `flashSale` data.
- **Discovery:** renders `DynamicBanner()` above product grid; also has footer `AdSlot` (AdMob) — **do not touch AdMob**.
- **`BannerRotator`:** cycles app sections (flash sale, seller boost promo for signed-in users, dynamic featured/earn-money fallback). Uses `Timer`/`AnimatedSwitcher`; has dwell-time logic respecting flash-sale count.
- **`FlashSaleBanner`:** PageView carousel of active sales, 30s auto-slide, lifecycle observer, routes to `AppRoutes.flashSale`. Uses product images/pricing/countdown/status.
- **`AdsPromoBanner`:** static internal promo (Boost), routes to `AppRoutes.boostProduct`. Signed-in targeting handled by rotator.
- **`DynamicBanner`:** `ProductService().getFeaturedProducts()` stream (created once). If products exist shows `_AdsCarousel` of boosted/featured products → product detail; else `EarnMoneyBanner` → add product.
- **`BannerService` (Firestore campaign system):** reads `banner_campaigns` (active, priority desc), caches by `BannerPlacement`, filters schedule/audience/limits (device/seller/business checks simplified), emits `bannersStream`. Records impressions/clicks to `banner_impressions`/`banner_clicks` (client does not mutate campaign counters). **Search indicates service/model/admin screen exist, but user-placement rendering integration is not wired** (no generic campaign banner widget consuming `bannersStream` in screens/widgets/ui).
- **Admin screen:** lists/filters campaigns, create/edit/preview/delete/duplicate hooks present in codebase; backend capabilities for uploads/preview parity/metrics must match existing Firestore/API support (do not invent unsupported backend).
- **`payment_banner.dart`:** transactional overlays (`PaymentBanner`, `RealtimePaymentBanner`), **not advertising**. Used by orders screens. Keep logic untouched except safe visual consistency if explicitly required; avoid payment-flow risk.

## AdMob separation (strict)
Do **not** modify: `lib/services/ads/*`, `AdMobService`, `lib/widgets/ads/*`, `AdSlot`, `AdPlacement`, interstitial/ad transitions/config. Keep admin/app promo banners independent from AdMob.

## UX/perf gaps to address incrementally
- Responsive sizing/cropping/text scaling for narrow phones, large phones, tablets, desktop/web.
- Reduced-motion support (`MediaQuery.disableAnimations`) for auto-rotation/animated transitions.
- Consistent Soko Vibe visual language (green/black/white, clean rounded surfaces, readable hierarchy, restrained decoration).
- Safe image handling: placeholders/error states, avoid layout jumps, keep caching where `ProductCachedImage`/existing loaders are used.
- Carousel accessibility: semantics, indicators, manual swipe preserved, pause behavior where appropriate.
- Reusable campaign presentation primitive that can render `BannerCampaign` (image/CTA/type/audience-safe display) and integrate with `BannerService` without breaking existing rotators.
- Admin preview improvements must stay within supported data/UI patterns.

## Image assets/licensing (cannot auto-generate/download licensed assets here)
- Prefer **existing Soko Vibe product images** (`ProductCachedImage`) and admin-uploaded `BannerCampaign.imageUrl/videoUrl` where available.
- For new static promo visuals, use **custom Flutter illustration/composition** or existing app assets; do **not** bake critical text into images.
- If external images are required later, source only from permissively licensed libraries (e.g., Unsplash/Pexels/Pixabay) with commercial-use verification and record source/license in this repo’s asset docs. **No random/watermarked/copyrighted assets were added in this pass.**

## Implementation plan (incremental)
1. Audit complete (this doc). Preserve all existing business logic, navigation, payment/auth/product flows.
2. Add shared banner primitives (theme-aware, responsive, reduced-motion, loading/error-safe) under existing widget/theme patterns.
3. Modernize `BannerRotator`, `FlashSaleBanner`, `AdsPromoBanner`, `DynamicBanner`/`EarnMoneyBanner` visuals and accessibility without changing data sources/routes/timing semantics.
4. Add reusable `CampaignBanner`/campaign card rendering for `BannerCampaign` + optional `BannerService` placement integration (non-breaking; do not inject into checkout/payment-critical flows).
5. Improve admin banner management preview/list ergonomics only if supported by current screen/service contracts.
6. `dart format` + `dart analyze` on touched files; run targeted tests if present. Report rendered visual verification limitations honestly.
## Implementation completed (this pass)
### New/updated files
- BANNER_ECOSYSTEM_AUDIT_2026-11-05.md — architecture audit, AdMob separation, image/licensing constraints, incremental plan.
- lib/widgets/banners/soko_banner_theme.dart — shared Soko Vibe banner primitives (radius/spacing/frame/max-width, badge/CTA, theme-aware surfaces). **No AdMob changes.**
- lib/widgets/banners/campaign_banner_card.dart — reusable renderer for admin BannerCampaign (type/sponsor labels, image fallback, CTA, destination routing, impression/click hooks via BannerService). Not injected into checkout/payment-critical flows.
- lib/widgets/banner_rotator.dart — responsive PageView carousel with swipe, interaction pause/resume, reduced-motion support, semantics, restrained indicators; preserves flash-sale dwell logic (30s × flash count) and signed-in boost promo + dynamic fallback composition.
- lib/widgets/flash_sale_banner.dart — premium responsive split layout, image/price/discount/CTA, 30s auto-slide preserved, lifecycle refresh preserved, interaction pause, reduced-motion support, tap → AppRoutes.flashSale.
- lib/widgets/ads_promo_banner.dart — internal Boost promo (NOT AdMob), premium responsive layout, tap → AppRoutes.boostProduct.
- lib/widgets/dynamic_banner.dart — featured product carousel + EarnMoneyBanner fallback preserved; responsive/reduced-motion/skeleton/loading-safe image handling; routes preserved (productDetail, ddProduct). Discovery/Home framing compatible with shared banner spacing.

### Preserved
- Existing flash-sale data/navigation (FlashSaleService, AppRoutes.flashSale), boost route, featured product/detail routes, ProductCachedImage caching behavior, PaymentBanner/RealtimePaymentBanner logic untouched, AdMob (ds/*, AdSlot, AdPlacement, interstitial/config) untouched.
- BannerService/BannerCampaign/admin screen contracts not broken; campaign rendering primitive added for integration.

### Verification (static)
- dart format on touched Dart banner files.
- dart analyze on touched banner/widgets/screens: **No issues found**.

### Not completed / limitations (honest)
- **Rendered visual verification not performed** (mobile/tablet/desktop, light/dark, text scaling, accessibility, screenshots). I cannot claim UI appearance without running the app.
- **No AI-generated/downloaded licensed image assets added.** Banners use existing product/admin images and safe Flutter/theme fallbacks; any future external assets must be sourced from licensed libraries with recorded source/license.
- **Admin campaign placement wiring into all user-facing placements** is not fully integrated in this pass (avoids risky cross-screen changes). CampaignBannerCard + BannerService are ready for incremental placement integration.
- **Admin banner management UI** was audited but not overhauled in this pass to avoid breaking unsupported backend operations; preview/list improvements can be done incrementally after confirming backend contract.
- **Targeted widget tests** for new banner components not added/run (no existing banner widget test suite identified). Full Flutter test/build not executed as part of this pass.
## Phase 2 status (2026-11-05 continuation)

### Completed
- Phase 1 visual verification: **not fully executable in this session** (no rendered Android/tablet device screenshots captured here). `flutter devices --machine` available targets seen: `windows` (screenshot capability false in machine output), `chrome`, `edge`; emulator `Pixel_6` listed earlier but not confirmed running. Static QA performed via `dart analyze` on touched banner files. **Do not claim production visual readiness.**
- Reusable admin campaign placement widget added: `lib/widgets/banners/campaign_banner_slot.dart` (`CampaignBannerSlot(placement: ...)`) using existing `BannerService`/`BannerCampaign`/`CampaignBannerCard`; deduplicates impression recording per widget instance; avoids checkout/payment-critical flows (no placements added there).
- `CampaignBannerCard` updated to support slot-controlled impression/click hooks (avoids double counting when used by slot).
- Admin preview: `admin_banner_management_screen.dart` preview dialog improved to use `CampaignBannerCard` rendering, with mobile/tablet/desktop width simulation and light/dark theme preview toggle (UI-only; no backend invention).

### Incomplete / limitations
- **No new licensed image assets generated or downloaded.** No external image sourcing performed (no verified-license downloads added). Banners continue to use existing product/admin images and safe Flutter fallbacks. Asset/license manifest still required if/when assets are sourced.
- Campaign placement wiring into all user screens is **partial/incremental** only where safe; full coverage (search/category/product detail/profile/wishlist/notifications/seller dashboard/flash sale) needs careful per-screen insertion and QA to avoid regressions and payment-flow risk.
- `BannerService` eligibility still has simplified client-side role/device assumptions (`isSeller/isBusinessAccount/deviceType`) — **client-side filtering is not security**; enforce sensitive targeting/scheduling/limits server-side or via secure rules/backend as needed.
- Targeted automated tests for banner eligibility/carousel/reduced-motion/fallback/tracking not yet added/run.
- Screenshots of actual UI not captured in this environment.

### Backend requirements (outstanding, not invented)
- Confirm/implement server-side enforcement for campaign audience targeting, schedule, impression/click limits, and secure media upload/hosting policies.
- Provide reliable user role/business/KYC/device targeting fields if client display must match policy (still enforce server-side).
- Aggregate analytics (CTR/impressions/clicks) source-of-truth: admin UI must not fabricate; use existing Firestore counters/events or backend aggregation endpoints.
