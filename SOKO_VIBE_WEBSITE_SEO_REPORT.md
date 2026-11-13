# SOKO VIBE WEBSITE — SEO REPORT

**Date:** 2026-11-09  
**Domain target:** https://www.sokovibe.co.tz (canonical)

## Implemented

- **Per-page metadata:** All 17 pages have unique title, meta description, canonical, Open Graph (title/description/image/width/height/alt), Twitter card, theme-color, `lang="sw"`, and JSON-LD. Generated once via `components.js` meta helper.
- **Structured data:** Organization + WebSite JSON-LD with verified-safe fields only (name, URL, logo, support email, area served TZ). No ratings, reviews, addresses, phone numbers, or fake relationships.
- **Sitemap (`landing/sitemap.xml`):** Updated to new page set (17 public pages, excluding 404/unsubscribe internals appropriately). Legacy paths excluded.
- **Robots (`landing/robots.txt`):** Allows crawling, references sitemap (`Sitemap: https://www.sokovibe.co.tz/sitemap.xml`).
- **Canonical/OG image:** `landing/assets/og-image.png` 1200×630 (verified dimensions, brand colors, text presence).
- **Favicon/manifest:** `manifest.json` updated (brand colors `#0A0A0A`/`#00C853`, `/assets/icon-192.png`, `/assets/icon-512.png`, `lang: sw`, `start_url: /`).
- **Semantic HTML:** Single `<h1>` per page (verified by CDP audit across 16 pages × 7 viewports), landmarks (`<main>`, `<header>`, `<footer>`, `<nav>`), alt text on all images (verified 0 missing).
- **Internal linking:** Header/footer/home CTAs link all pages; mobile menu includes all nav items.
- **Bilingual crawlability:** Kiswahili content in HTML (default, crawlable); English via `data-en*` attributes swapped by JS. hreflang tags present.
- **Legacy redirects:** 301s for old URLs (see audit). `/data-deletion` and `/about/founder` retained.
- **Performance for SEO:** Lighthouse SEO 100 on home + pricing + faq + contact + about (mobile). LCP 1.1–1.2s mobile, 0.3s desktop. CLS 0. Total page weight 35–57 KB, no external fonts.

## Lighthouse SEO Scores (Mobile, Throttled)

| Page | SEO | Performance | Accessibility | Best Practices |
|---|---|---|---|---|
| `/` | 100 | 97 | 100 | 100 |
| `/pricing` | 100 | 99 | 100 | 100 |
| `/faq` | 100 | 100 | 100 | 100 |
| `/contact` | 100 | 98 | 100 | 100 |
| `/about` | 100 | 99 | 100 | 100 |

Desktop home: Performance 100, Accessibility 100, Best Practices 100, SEO 100.

## Hosting/Redirect Behavior

- Express (`src/app.js`) serves landing static files and handles 301s for legacy + `.html` paths plus branded 404.
- `_redirects` updated for static-host parity: legacy 301s only; removed SPA fallback `/* /index.html 200` (no longer a SPA). Unknown paths fall to `404.html`.
- Canonical domain enforcement (`sokovibe.co.tz` → `www.sokovibe.co.tz`) and HTTPS enforcement are deployment/edge responsibilities; verify in Cloudflare/Render config.

## AI Discoverability / Semantic Clarity

- Clear semantic page structure; accurate pre-launch status messaging to prevent misleading summaries.
- No keyword stuffing; natural Tanzanian marketplace intent coverage (Swahili + English).

## Gaps / Follow-up

- Google Search Console verification, sitemap submission, index inspection require authorized access — not performed.
- Per-route metadata is now real static HTML (stronger than SPA). No prerender gap remains for the new system.
- Hreflang is present; localized URL prefixes not used (in-app switch). Acceptable for current scope.
- Field Core Web Vitals data requires production RUM/Search Console.