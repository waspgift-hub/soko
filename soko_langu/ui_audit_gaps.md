# UI/UX Redesign Gap Report — Soko Vibe (audit at commit 81fb4f4)

Generated from a full repo audit. Foundation already strong; below are the
*deltas* to close per the UI/UX specifications (sections 1-30).

## Already in place (do NOT redo)
- theme/app_colors.dart: semantic dark/light tokens incl. brand green #00C853,
  WhatsApp green (#25D366) preserved for brand trust, contrast-safe.
- theme/app_typography.dart: Inter + Space Grotesk + JetBrains Mono scale.
- theme/app_dimens.dart: 8pt spacing grid (4..64), radii, font sizes.
- lib/widgets/ds/: 25 components (button, card, chip, price, rating, avatar,
  skeleton, empty/error states, verified badge, sheet, quantity selector,
  ad badge, ...).
- 26 screens already responsive (MediaQuery/LayoutBuilder); 68 files analyze clean;
  249 tests green.

## Gap A — Hardcoded TextStyle (migrate to DS tokens)
Counts per file (≈ totals; top offenders):
  admin_dashboard_screen       78
  search_screen                52
  product_detail               40
  discovery_screen             30
  seller_earnings_screen       42
  seller_analytics_screen      29
  sponsored_dashboard_screen   14
  kyc_screen                   27
  checkout                     19  (many remain)
  chat_page                    34
  plus ~20 more screens (5-20 each).
Files with 0-3 (reference clean style): buyer_requests_screen (trError),
  ads_promo_banner, notification_lang, etc.

## Gap B — Spacing (non-8pt padding, 48 sites)
- discovery_screen:145 raw EdgeInsets (will migrate to AppInsets).
- 40+ screens: EdgeInsets/Padding literals falling outside {4,8,12,16,20,24,32,40,48}.

## Gap C — Raw material colors (risky, migrate to tokens)
- lib/screens/notification/notification_screen.dart:1 (Colors.*)
- lib/screens/admin/admin_kyc_screen.dart (Colors.*)
- 72 raw color/Shadow uses across screens.

## Gap D — Duplicated UI patterns (consolidate into ds/)
- Search input: repeated across discovery/search screens => build DsSearchBar.
- Section header: repeated section-title + "see all" => DsSectionHeader.
- Price emphasis / old-price strikethrough => exists (DsPrice); migrate call sites.

## Suggested batch order (each = analyze + test green, then commit)
1. network_error/product_api/sponsored/kyc/review error-label fix  (DONE, 81fb4f4)
2. DS additions: DsSearchBar, DsSectionHeader (+ tests).
3. Theme-token sweep: discovery_screen (flag-ship) => tokens + responsive grid.
4. search_screen + product_detail hardcoded TextStyle -> DS.
5. Remaining screens (split by area: seller, admin, chat, kyc).
6. Final: full analyze + flutter test + visual review light/dark + golden.

Files intentionally left untracked (tooling/artifacts; ask before ever committing):
  .kilo/, .opencode/, android/build/reports/problems/problems-report.html,
  root v3_verification_test.js.
