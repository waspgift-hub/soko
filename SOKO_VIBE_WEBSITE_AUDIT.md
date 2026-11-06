# SOKO VIBE WEBSITE — PRE-LAUNCH AUDIT

**Date:** 2026-11-06  
**Scope:** Audit of existing Soko Vibe website codebase and safe pre-launch repair planning (no production deployment performed).  
**Website target:** https://www.sokovibe.co.tz  
**Codebase inspected:** `web_landing/` (Flutter Web marketing/landing app) and supporting server endpoints under `soko_langu/server/src/`.

## Summary
The site is implemented as a **Flutter Web single-page pre-launch landing** (`web_landing/`). It already includes a real waitlist form (`lib/services/launch_api.dart`) posting to `POST /api/v1/launch/subscribe` (`SOKO_API_BASE` default `https://soko-langu-server.onrender.com`). The server has launch/waitlist routes (`soko_langu/server/src/modules/launch/routes.js`, mounted in `server/src/app.js`) and admin landing endpoints (`server/src/modules/admin/routes.js`).

**Not production-ready as-is for the requested pre-launch conversion goal.** Key gaps: requested Swahili hero/CTA copy not fully matched; privacy/terms links point to external paths (`/privacy-policy`, `/terms-of-service`) but SPA has no in-app routes and sitemap has only `/`; missing/weak localization key (`nav_menu` used but not defined in `app_strings.dart`); no explicit cookie/consent policy page; security headers lack CSP/HSTS (deployment-dependent); no evidence of email double opt-in/verification flow where supported; subscriber export/view access is admin-secret based server-side but needs a clear admin-accessible operational path; Flutter Web bundle/performance and accessibility need measured verification; SEO needs per-page metadata strategy (limited by SPA) and structured data review.

## 1. Codebase / Deployment Inventory
- **Frontend:** `web_landing/` — Flutter Web (`pubspec.yaml` `soko_vibe_web`, Dart `^3.11.5`, deps: `http`, `visibility_detector`, `url_launcher`).
- **Entry/UI:** `lib/main.dart`, `lib/pages/landing_page.dart`, `lib/sections/coming_soon_sections.dart`, `lib/sections/site_nav.dart`, `lib/localization/app_strings.dart`, `lib/services/launch_api.dart`.
- **Web assets/config:** `web_landing/web/index.html`, `manifest.json`, `robots.txt`, `sitemap.xml`, `_headers`, `_redirects`, icons/favicons, `build/web/*`.
- **Backend (existing):** `soko_langu/server/src/modules/launch/routes.js` — `POST /api/v1/launch/subscribe` (rate limit 8/15min/IP, honeypot+timing spam checks, Zod validation, email normalization/validation, duplicate prevention via `landing_waitlist` doc keyed by email, stores `name/lang/source/createdAt/updatedAt/duplicateSignupCount`), `GET /subscribers`, `GET /subscribers/export` (admin secret via `verifyAdminSecret` / `x-admin-secret`).
- **Admin landing:** `soko_langu/server/src/modules/admin/routes.js` reads/broadcasts `landing_waitlist` (SMTP broadcast). Collection naming overlaps conceptually with launch module (`landing_waitlist`) — must preserve compatibility.

## 2. Audit Findings

### 2.1 Homepage / Messaging (Pre-launch)
- **Status:** Partially aligned.
- **Evidence:** Hero shows “Your Marketplace. Your Community. Your Vibe.” and “Soko Vibe is… under development — register your email…” (`app_strings.dart` `hero_title/hero_sub`, `badge_under_dev`). Register form exists.
- **Gaps:** User-requested hero headline `Soko la Tanzania, Hivi Karibuni.` and Swahili description/primary CTA `NIJULISHE APP IKIZINDULIWA` / secondary `JIFAHAMU ZAIDI` not fully implemented. “Coming Soon”/under-development indicators exist but should be explicit and consistent. Features copy must avoid claiming live operational features.

### 2.2 Navigation / Footer / Internal Pages
- **Status:** Incomplete for legal/support routes.
- **Evidence:** Single-page sections via scroll (`landing_page.dart`). Footer links use `SokoLinks.privacy='$site/privacy-policy'`, `terms='$site/terms-of-service'` (`models/models.dart`) opened via `openLink`/`url_launcher` external app (`widgets/open_link.dart`).
- **Gaps:** No in-app routes/pages for Privacy/Terms/Support/FAQ-as-page/Cookie. `_redirects` sends all paths to SPA (`/* /index.html 200`), so external links to `/privacy-policy`/`terms-of-service` will load SPA but content will not render as dedicated legal pages unless router/pages added. Missing `nav_menu` key used in `site_nav.dart:54` (not found in `app_strings.dart`; locale parity test passes because it compares existing sw/en key sets — missing in both does not fail). Support/contact limited to email.

### 2.3 Legal Pages (Privacy, Terms, Cookie, Contact)
- **Status:** Missing/externally referenced; content accuracy unverified.
- **Gaps:** No Privacy Policy, Terms of Service, or Cookie Policy pages in `web_landing`. Waitlist form states “We’ll only use your email…” but no full policy page describing actual collection (email/name/lang/source/timestamps/IP handling if any, admin export/broadcast, retention, rights, Tanzania/data-protection posture). Must accurately reflect real data collection/services and avoid unsupported claims.

### 2.4 Email Waitlist / Forms
- **Status:** Real backend exists; needs hardening/UX/verification assessment.
- **Evidence:** Frontend validates email, loading/success/error/duplicate states, honeypot offstage field, `formStartedAt` (`coming_soon_sections.dart`, `launch_api.dart`). Backend has rate limiting, Zod validation, honeypot/timing checks, duplicate prevention, secure-ish storage via `commerceStore`/Firestore admin path. Export/list require admin secret.
- **Gaps/Risks:** No double opt-in/email verification token flow found in `launch/routes.js` (requirement asks “Email verification where supported” — implement safely if supported by existing mailer/infrastructure without breaking current flow; otherwise document). Success message required by user differs from current strings. Admin-accessible view/export exists as protected API endpoints, but no simple admin UI in `web_landing`; operational path must be documented or safely added within existing infra. Must not expose subscriber emails publicly. No explicit consent checkbox/cookie notice (privacy-conscious handling).

### 2.5 SEO Metadata / Sitemap / Robots / Structured Data
- **Status:** Partial.
- **Evidence:** `web/index.html` has title/description/canonical/OG/Twitter/geo/robots meta and Organization+WebSite JSON-LD. `robots.txt` allows all and references sitemap. `sitemap.xml` contains only homepage.
- **Gaps:** User-requested title/meta targeting and Swahili pre-launch positioning may need update. SPA cannot set per-route metadata after client navigation without extra setup; legal pages need indexable strategy. Sitemap must include legal pages if added as real URLs. Heading hierarchy/image alt attributes need code-level verification. Keywords should be natural (no stuffing).

### 2.6 Security Headers / Security
- **Status:** Partial (host-dependent).
- **Evidence:** `web/_headers` sets `X-Content-Type-Options`, `X-Frame-Options: DENY`, `Referrer-Policy`, `Permissions-Policy`; cache headers.
- **Gaps:** No `Content-Security-Policy`, `Strict-Transport-Security`, `Cross-Origin-Opener-Policy`/`Cross-Origin-Resource-Policy` as applicable. Flutter Web CSP can be tricky (wasm/canvaskit/inline bootstrap); must apply safely per deployment platform. No secrets exposed in inspected frontend files. Subscriber endpoints protected by admin secret but need transport/operational security review.

### 2.7 Performance / Accessibility / Responsiveness
- **Status:** Not measured.
- **Evidence:** Flutter Web release build output exists (`build/web`), bundled fonts, responsive layout patterns in code, reduced-motion consideration in reveal widget likely present. Images/icons present; OG points to `icons/Icon-512.png`.
- **Gaps:** No Lighthouse/PageSpeed evidence captured. Flutter Web canvas/DOM tradeoffs affect Core Web Vitals; optimize what is safe (assets, caching, font loading, deferred loading) without breaking functionality. Accessibility (semantics labels, contrast, focus, form labels, language attributes for SW/EN) needs verification. Mobile/tablet/desktop responsive QA needed.

### 2.8 Broken Links / Console / Network / Tests
- **Status:** Partially tested.
- **Evidence:** `flutter test` in `web_landing` passed (4 tests: locale parity, smoke). `flutter analyze` output file was created but content capture was inconclusive in this session; needs rerun and recording.
- **Gaps:** Footer legal links likely broken as dedicated pages. No browser console/network audit run against built site. No end-to-end test against live/real subscribe endpoint. `nav_menu` missing key is a runtime localization smell.

### 2.9 Misleading / Incomplete Claims
- **Risk:** Medium.
- Features are presented as planned (“being built/designed/aims”) in places, but copy must be reviewed to ensure no feature is claimed live. Hero title currently branding-focused, not matching requested pre-launch Swahili conversion copy.

## 3. Safe Implementation Plan (next)
1. **Localization/copy:** Add missing `nav_menu` key (SW/EN), update hero/CTAs/success/privacy copy to required pre-launch Swahili/English messaging, preserve locale parity tests.
2. **Legal & trust pages:** Add real in-app routes/pages for Privacy Policy, Terms of Service, Cookie Policy (if applicable), Contact/Support info, with accurate waitlist data handling. Use simple indexable static pages or Flutter routes + sitemap entries; preserve SPA behavior safely.
3. **Waitlist UX/security:** Keep real backend integration; improve success message (`Asante!...`), add explicit privacy/consent text, strengthen client validation/rate-limit UX, document/admin-access path for subscriber view/export without exposing public emails. Assess email verification feasibility with existing mailer; implement only if safe and supported.
4. **Sections:** Add/adjust Buyers, Sellers, Security & Trust sections with honest “planned/under development” framing and no unsupported claims; add relevant “Coming Soon” labels.
5. **SEO/security/perf:** Update metadata, structured data, sitemap/robots, image alts, safe headers (CSP/HSTS where host supports), build/test, and record evidence. Avoid risky rewrites.

## 4. Files/Areas Likely to Change
- `web_landing/lib/localization/app_strings.dart`, `models/models.dart`, `pages/*`, `sections/*`, `widgets/open_link.dart`, `main.dart` (routing if needed)
- `web_landing/web/index.html`, `robots.txt`, `sitemap.xml`, `_headers`, possibly legal static files
- `web_landing/test/*` (update/add coverage for new behavior)
- `soko_langu/server/src/modules/launch/routes.js` and/or email templates only if safe/necessary for verification/admin access; preserve existing endpoints/collections
- Reports: `SOKO_VIBE_WEBSITE_AUDIT.md` (this file), `SOKO_VIBE_WEBSITE_REPAIR_REPORT.md` (after implementation/testing)

## 5. Audit Limitations
- No live browser console/network trace against https://www.sokovibe.co.tz in this session.
- No production deployment, DNS/host header, or PageSpeed/Lighthouse run evidence yet.
- Backend runtime not exercised against live database/mailer; findings are static plus existing test evidence. Email verification “where supported” depends on deployed mailer/domain/token configuration.