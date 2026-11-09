# SOKO VIBE WEBSITE — TEST REPORT

**Date:** 2026-11-09  
**Environment:** Windows workspace, Node.js v24.15.0, Chrome (headless) via CDP.

## Automated Tests / Checks Executed

| Check | Scope | Result | Notes |
|---|---|---|---|
| `node tools/site/build.js` | `soko_langu/server/landing` | **PASS** | 17 pages built; validation passes (titles/canonicals/internal links). |
| `node --test test/public-form.test.js` | server | **PASS** | 11 tests (normalizeEmail, isValidEmail, isSpam, hashValue, hashIp, randomToken). |
| `node --test test/launch-contact-routes.test.js` | server | **PASS** | 9 tests (subscribe consent/IP/token/email, duplicate, unsubscribe + replay + fresh consent, invalid token, validation, honeypot, contact store+notify, consent/short message, notification failure tolerance). |
| `node --test test/*.test.js` (excl. live) | server | **PASS** | 619 tests, 614 pass, 0 fail, 5 skip, 42 suites, ~9.5s. |
| `npm test` (incl. live) | server | **PARTIAL** | 684 tests, 675 pass, 4 fail, 5 skip. The 4 failures are live-deployment drift in `e2e.live.test.js` (unauthenticated endpoints return 400/404 instead of 401/403/429), not local regressions. |
| `node --check` (7 files) | server | **PASS** | app.js, launch/routes.js, contact/routes.js, public-form.js, admin/routes.js, seo/routes.js, seo/sitemaps.js. |
| Browser/CDP responsive + bilingual | 16 pages × 7 viewports | **PASS** | 912 checks, 0 failures (360/390/430/768/1024/1440/1920). Single h1, alt text, landmarks, no horizontal overflow, no offscreen elements, correct nav mode per breakpoint, mobile menu open/Escape/focus, language switch/translation/persistence/URL, English validation + `aria-invalid`. |
| Local smoke test | server (port 3100) | **PASS** | 161 checks, 0 failures: 17 pages, legacy/`.html` 301s, branded 404, sitemap/robots, waitlist/contact validation, honeypot silent success, 429 rate limits. |
| Lighthouse (mobile) | home/pricing/faq/contact/about | **PASS** | See table below. |
| Lighthouse (desktop) | home | **PASS** | 100 all categories; LCP 0.3s, CLS 0, TBT 0. |
| INP proxy (interaction latency) | home (mobile) | **PASS** | Worst case 117ms (language switch re-render) < 200ms target; desktop 35ms. |
| OG image verification | `landing/assets/og-image.png` | **PASS** | 1200×630, 87,292 bytes, verified dimensions/colors/text presence. |
| Contrast check | `--sv-gray-400` | **PASS** | Changed `#8b918b` (3.0:1) → `#6b6b6b` (4.96:1 on `#f6f7f6`); Lighthouse color-contrast 100. |

## Lighthouse Scores (Mobile, Throttled)

| Page | Performance | Accessibility | Best Practices | SEO | LCP | CLS | TBT |
|---|---|---|---|---|---|---|---|
| `/` | 97 | 100 | 100 | 100 | 1.2s | 0 | 200ms |
| `/pricing` | 99 | 100 | 100 | 100 | 1.2s | 0 | 130ms |
| `/faq` | 100 | 100 | 100 | 100 | 1.1s | 0 | 70ms |
| `/contact` | 98 | 100 | 100 | 100 | 1.1s | 0 | 150ms |
| `/about` | 99 | 100 | 100 | 100 | 1.1s | 0 | 130ms |

Page weight: 35–57 KB total; no external fonts/JS dependencies.

## Tests Updated / Added

- `soko_langu/server/test/public-form.test.js` (new, 11 tests).
- `soko_langu/server/test/launch-contact-routes.test.js` (new, 9 tests).
- `landing/tools/site/build.js` validation covers titles/canonicals/internal links.

## Manual / Not Executed

- `eslint src/` — eslint not installed in environment (package.json declares lint script but eslint is not a dependency). `node --check` used instead.
- `flutter build web --release` — not applicable (public surface moved off Flutter Web).
- Live E2E: 4 failures are production drift, not local regressions (see above).
- Google Search Console verification/sitemap submission require authorized access — not performed.
- Real-device screen-reader audit not performed; Lighthouse accessibility 100 + CDP keyboard/focus checks pass.

## Known Test Gaps

- Contact endpoint has route-level tests (9) but no live integration against production Firestore/mail.
- No visual regression/screenshot diff tests; Lighthouse + CDP responsive checks provide coverage.
- Legal content accuracy is a content review, not an automated test.

## Production Build Status

- Generator build: 17 pages, validation passes.
- Server: syntax + 619 unit tests pass (excl. live); 4 live-drift failures documented.
- Deployment: not performed; no DNS/production config changed. Backend deploy requires authorization.