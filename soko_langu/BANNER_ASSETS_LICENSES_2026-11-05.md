# SOKO VIBE BANNER ASSETS & LICENSING (2026-11-05)

## Scope
This file documents banner/campaign visual assets for the in-app banner ecosystem (NOT AdMob). Phase 2 requires a professional image library and source/license records.

## Status: NOT COMPLETED (limitation)
- **No AI-generated banner images were created** in this environment/session.
- **No online images were downloaded** (Unsplash/Pexels/Pixabay or other sources) in this session, because I cannot verify licenses/permissions end-to-end or safely store third-party binaries without explicit approval in this workflow.
- **No random, watermarked, or unlicensed copyrighted images were used.**

## Current safe image behavior
- `DynamicBanner` / featured carousel uses **existing Soko Vibe product images** loaded via `ProductCachedImage` (existing cache/placeholder behavior).
- `FlashSaleBanner` uses **existing flash sale/product images**.
- `AdsPromoBanner` and `EarnMoneyBanner` use **theme-aware Flutter UI/icon compositions** (no baked critical text inside raster images).
- `CampaignBannerCard` / `CampaignBannerSlot` render admin `BannerCampaign.imageUrl`/`videoUrl` when present, with safe visual fallbacks.

## Required categories (to be sourced/licensed later)
Create/license assets for: sponsored advertisements, marketplace promotions, flash sales, seller promotions, new feature announcements, wallet promotions, delivery promotions, seasonal campaigns, start selling campaigns.

## Sourcing rules (must follow when adding assets)
1. Prefer **original Soko Vibe product/brand assets** or **admin-uploaded campaign assets**.
2. If external assets are needed, use only commercially licensed libraries (e.g., Unsplash, Pexels, Pixabay) **after verifying each asset’s license and permitted commercial use**.
3. Record for every asset: filename/path, category, source URL, author (if provided), license name/URL, download date, usage notes, and any attribution requirements.
4. Optimize for mobile/web (WebP/AVIF where supported; avoid oversized originals). Do not bake critical text/CTA into images; render text in Flutter.
5. Keep Soko Vibe brand consistency (green/black/white/neutral, clean premium marketplace look).

## Asset manifest template
| Asset | Category | Source | Author | License | URL | Added | Notes |
|---|---|---|---|---|---|---|---|
| *(none added in this pass)* |  |  |  |  |  | 2026-11-05 | Limitation documented |
