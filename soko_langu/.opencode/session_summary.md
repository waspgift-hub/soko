# Soko Vibe — Session Summary

## Objective
Replace the legacy per-product "boost" system entirely with the professional sponsored **ads** system: zero boost branding/UI in the Flutter app ("sitaki kuona boost kabisa kwenye app"), boost banner → ads promo banner, ads activation via ClickPesa webhook, real ad serving across placements, daily budget pacing, click attribution. Server ads work is done; Flutter de-boosting is now COMPLETE and all suites are green.

## Important Details
- User directive (Swahili): "remove boost system ibaki ads; boost banner → ads banner; kila kitu cha boost kiwe cha ads; sitaki kuona boost kabisa kwenye app."
- Architecture: Firestore-only store seam; entrypoint `src/index.js`; Render auto-deploys from `master`; no Postgres. Do NOT run real ClickPesa/SMS; no fake data; keep server `.env` out of commits.
- Seam behaviors: relation clauses in `where` ignored; `include` resolves via declared `RELATIONS`; in-memory post-filter CAP=1000. `getStore()` singleton; `getReadStore()` returns same instance.
- Sponsored campaign state machine: draft → payment_pending → active → (paused|completed|cancelled) + rejected/expired/out_of_budget; 8 `PLACEMENT_TYPES`; webhook routes `camp_` orderReferences to `confirmPayment`.
- Legacy boost (server `legacy-compat`) serves the OLD mobile app — decision: keep server legacy boost endpoints intact (avoids breaking old clients/payment orphanage); de-boosting targets the Flutter app only.
- Product model KEEPS parsing `isBoosted`/`boostedUntil`/`boostTier` (SURVIVES-INTERNAL decision — server legacy may return them; round-trip tests assert them). ProductApiClient keeps `boosted:` query param. NO UI consumes any of these; no user-visible "boost" remains in the app.
- Flutter/Dart: Flutter 3.41.9, Dart 3.11.5. `flutter analyze --no-pub` clean (2 pre-existing infos: dangling_library_doc_comments zh_translations.dart:1, no_leading_underscores search_intent.dart:76 — unrelated). `flutter test --no-pub` = 249 pass. Server `node --test test/*.test.js` from `soko_langu/server` = 321 pass.
- `ApiConfig.kUseProductsApi = true` (HTTP API path live; Firestore branch in `getFeaturedProducts` is fallback-only, already de-boosted).

## Work State
### Completed (all verified)
- Server ads edits (UNCOMMITTED, all 321 tests pass): `firestore-store.js` RELATIONS `sponsoredCampaign.placements`/`.payment`/`.auditLogs`, `campaignPlacement.campaign`/`.product`, money field `dailySpendTzs`; `sponsored-service.js` (dayKey, createCampaign writes real campaignPlacement rows + isAllProducts, rewritten getActivePlacements with cache/impression-dedupe/daily budget/serving filters, sweepCampaignStatuses daily reset + 24h stale pending expiry, activateCampaign seeds buckets); `payment-service.js` `camp_` webhook → confirmPayment; `product-service.js` PUBLIC_SELECT → categoryId, sponsorMap/isSponsored/sponsoredCampaignId re-rank; `feed-service.js`+`routes.js` AD_SLOTS=[1,5] interleave on page 1 + ipAddress/userAgent threading.
- Flutter boost file deletion (8): boost_service.dart, boost_tier.dart, boost_receipt.dart, boost_receipt_screen.dart, product_boost_screen.dart, boost_promo_banner.dart, boost_receipt_card.dart, ds_boost_badge.dart.
- Routes/notifications: routes.dart removed `productBoost`+`boostReceipt`; router.dart removed imports+GoRoutes+authRequiredRoutes entry; main.dart removed `case 'boost'`; notification_service.dart removed `case 'boost'`; notification_screen.dart removed empty `case 'boost'`.
- Ads banner: `lib/widgets/ads_promo_banner.dart` (new, sponsored keys, links AppRoutes.sponsoredDashboard); banner_rotator mounts it (gated on FirebaseAuth currentUser); `banner_rotator.dart:47` comment now "dynamic/ads".
- `lib/widgets/ds/ds_ad_badge.dart` (DsAdBadge, black pill + `tr('sponsored')`); ds.dart export swapped; feed_post_card.dart shows DsAdBadge on `product.isSponsored`.
- dynamic_banner.dart: `_BoostedCarousel`→`_AdsCarousel`, `tr('boosted')`→`tr('sponsored')`.
- product_service.dart: getFeaturedProducts HTTP sponsored-first, Firestore fallback de-boosted; `_sortByPublished`→`_sortBySponsored` (10 call sites); internal vars `aBoosted/bBoosted`→`aSponsored/bSponsored`; create comment reworded (server-owned promotion fields).
- product_api.dart: removed unused fetchFeatured; kept `boosted:` param (legacy/internal).
- search_screen.dart: discovery sponsored-first; Firestore fallback de-boosted; discovery partition `boosted`→`sponsored` vars; Ad pill gates `r.isSponsored`; comments 67/132-134 reworded.
- discovery_screen.dart: forYou sort uses isSponsored.
- search_service.dart: SearchResult.isBoosted field REMOVED (had zero consumers); isSponsored + kycApproved mapped.
- Seller boost cards removed: my_purchases (isBoost var, boost dispatch, _buildBoostCard), seller_analytics (_buildBoostsCard), help_center (boosting tile), admin_clickpesa (boostRevenue var + boost_revenue row; duplicate adRevenue var fixed).
- Analytics fully stripped: analytics_models.dart removed boostImpressions/boostLocationBreakdown + BoostImpressionRecord; analytics_service.dart removed trackBoostImpression, getBoostStats, all boost locals/aggregation/Future.wait entries, admin assembly args, EN/SW Groq prompt lines. Grep confirms zero boostImpressions/boostLocationBreakdown/BoostImpressionRecord/_boostImpressions/getBoostStats anywhere in lib.
- Colors/constants: app_colors.dart removed boostGold/boostSilver/boostBronze; constants.dart removed boostTiers (constants_test.dart was empty).
- discovery_filters.dart:138 popular sort now uses isSponsored.
- Localization COMPLETE: removed 46+14 boost keys from localization_service.dart (incl. multiline help_boosting key+value, orphan boost_complete value), 23+7 from zh_translations.dart; notification_lang.dart removed 3 boost title rules + 4 body rules. Reworded free-text: SW Terms "3.10 KUPIGA BIDHAA (BOOST)"→"3.10 MATANGAZO (SPONSORED ADS)", EN Terms "8.5 BOOST AND PROMOTIONAL FEES"→"8.5 ADVERTISING AND PROMOTIONAL FEES", EN Privacy "boosted, or removed"→"advertised, or removed", EN feature bullet "Product Boost - Feature your products"→"Sponsored Ads - Promote your products". Grep confirms ZERO "boost"/"Boost" in localizations.

### Known remaining "boost" (INTENTIONAL, internal-only)
- `lib/models/product_model.dart`: legacy parse fields isBoosted/boostedUntil/boostTier + isBoostedValid getter + round-trip toJson (SURVIVES-INTERNAL).
- `lib/services/product_api.dart:41,59`: `boosted:` query param (legacy/internal).
- Tests: product_full_test.dart + product_api_test.dart cover those model fields/param.
- NOTE: the Grep tool returned stale/half line numbers on localization_service.dart this session (trusted Select-String + Read instead; Grep tool output had encoding/CRLF-based misnumbering).

### Blocked
- No Render dashboard/CLI/env access (secrets inferred at runtime only).
- Real ClickPesa/SMS not testable (real money/SMS).
- Uncommitted: server ads edits + entire Flutter de-boost change set are uncommitted; NOT committed/pushed (no explicit request).
- Production smoke verify not yet run (needs deploy via master push).

## Next Move
1. If user confirms: commit (server + Flutter) and push `master` (Render auto-deploy). Inspect `git status`/`git diff` first; stage intended files; never commit secrets; match repo commit style.
2. Production smoke verify after deploy: feed ad slots (AD_SLOTS=[1,5]), search placements (sponsored-first), webhook activation path (`camp_` → confirmPayment), AdsPromoBanner on home.

## Relevant Files
- Server (UNCOMMITTED): `server/src/modules/sponsored/sponsored-service.js`, `server/src/modules/payments/payment-service.js`, `server/src/services/firestore-store.js`, `server/src/modules/products/product-service.js`, `server/src/modules/feed/feed-service.js` + `routes.js`. Legacy: `server/src/modules/legacy-compat/feature-compat.js` (kept intentionally).
- Flutter (UNCOMMITTED): deleted 8 boost files; `lib/widgets/ads_promo_banner.dart`, `lib/widgets/ds/ds_ad_badge.dart`, `lib/services/analytics_service.dart`, `analytics_models.dart`, `search_service.dart`, `product_service.dart`, `search_screen.dart`, `discovery_filters.dart`, `app_colors.dart`, `constants.dart`, `localization_service.dart`, `zh_translations.dart`, `notification_lang.dart`, `notification_service.dart`, `notification_screen.dart`, `my_purchases_screen.dart`, `seller_analytics_screen.dart`, `help_center_screen.dart`, `admin_clickpesa_screen.dart`, `dynamic_banner.dart`, `feed_post_card.dart`, `banner_rotator.dart`, `routes.dart`, `router.dart`, `main.dart`.