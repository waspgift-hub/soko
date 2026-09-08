# Soko Vibe — Technical SEO & AI-Discoverability Report (Sections A–T)

Target site: **https://www.sokovibe.co.tz/** (canonical host; apex `sokovibe.co.tz` 301-redirects to it)
Repo: `ttr/soko_langu` (branch `master`), deployed server = `server/src/index.js` → `server/src/app.js`.
All changes are **additive**: no business/financial/API/auth/escrow/chat logic was modified.

---

## A. Executive summary

Crawlers and AI systems previously saw an inconsistent homepage title/description ("Soko Vibe — Buy and Sell Anything Locally") and a mix of entity descriptions across pages. This work makes every publicly served page resolve to **one identical Organization entity** — a Tanzania-based online marketplace — verified by a scripted JSON-LD graph check and a 110-assertion crawler simulation that passes 100%.

Delivered: consistent `<title>`, meta description, H1 + visible entity statement, geo targeting, social (`og:`/`twitter:`) tags with sized preview image, a full Organization/WebSite/Person/FAQPage/BreadcrumbList structured-data graph, 3 new informational pages (`/how-soko-vibe-works`, `/soko-vibe-fees`, `/soko-vibe-escrow`), expanded sitemap, hardened robots.txt, noindex-able slashes collapsed, HTTPS-only folding, an enhanced 404, and an IndexNow submission helper.

## B. Entity identity baseline

- Brand name must always be written **"Soko Vibe"** (legal entity "Soko Vibe Limited" appears only where legally required — site footer).
- Official short entity statement (used verbatim in `meta.description`, JSON-LD `description`, and one ARIA-visible `.en` block on every page except legal):

  > Soko Vibe is a Tanzania-based online marketplace connecting buyers and sellers across Tanzania.

- Official long entity statement (used on the homepage intro): "Soko Vibe is a Tanzania-based multi-vendor online marketplace operated in Dar es Salaam, Tanzania, enabling buyers and sellers to discover, list, buy and sell products and services online with secure transactions, seller verification, communication tools and delivery support."
- These exact strings are held in `server/src/seo/meta.js` (`description`, `longDescription`) and reused by pages and checks — a single source of truth.

## C. Target entity definition (single source of truth)

| Property | Value |
|---|---|
| `@id` (Organization) | `https://www.sokovibe.co.tz/#organization` |
| `@id` (WebSite) | `https://www.sokovibe.co.tz/#website` |
| `@id` (founder, Person) | `https://www.sokovibe.co.tz/#founder` |
| Name / brand | Soko Vibe |
| Description | Official short statement (above) |
| Email | `support@sokovibe.co.tz` |
| Telephone | `+255 69 327 3241` (from `server/src/config`) |
| Address / area served | Dar es Salaam, TZ · `areaServed: Tanzania` |

No `sameAs` (no verified official social profiles yet), no `hreflang` (JS language toggle uses one URL, so hreflang would be incorrect), no invented ratings/reviews/prices/sellers.

## D. Changed files (14 modified, 4 new)

**Server config**
- `server/src/seo/meta.js` — email fixed to `support@sokovibe.co.tz`; `description` = official short statement; added `longDescription`.
- `server/src/seo/sitemaps.js` — sitemap now lists all public pages (see K).
- `server/src/seo/routes.js` — robots.txt + IndexNow route + upgraded 404 page.
- `server/src/app.js` — HTTPS-only fold, trailing-slash collapse, new page registrations.

**Landing pages (edited)** — `index.html`, `about.html`, `about-founder.html`, `categories.html`, `tanzania-marketplace.html`, `support.html`, `privacy.html`, `terms.html`.
**Landing pages (new)** — `how-soko-vibe-works.html`, `soko-vibe-fees.html`, `soko-vibe-escrow.html`.
**Verify tooling** — `server/scripts/seo-check.js` (extended), `server/scripts/seo-jsonld-check.js` (extended), `server/scripts/indexnow-submit.js` (new).

> `hosting/` is a legacy Firebase-Hosting mirror and is **not** deployed; it was left untouched (any edits there would not go live — see T).

## E. Homepage (`/`)

- `<title>` → `Soko Vibe — Tanzania Online Marketplace | Buy & Sell in Tanzania` (≤60 chars, includes H1 keywords).
- `meta[name=description]` → official short statement.
- H1 → `Soko Vibe — Tanzania Online Marketplace`; visible subheading kept in Swahili ("Nunua na uza bidhaa Tanzania kwa urahisi, usalama na urahisi wa kuwasiliana na wauzaji…").
- Intro section gains an ARIA-visible English block containing the short **and** long official entity statements for text crawlers / AI extractors.
- Geo meta added: `geo.region` = `TZ`, `geo.placename` = `Dar es Salaam, Tanzania`.
- FAQPage JSON-LD (fees/escrow/how-it-works) preserved — the only page carrying it.
- OG/Twitter: `og:image` now carries `width`/`height`/`alt`; `twitter:image:alt` added; titles/descriptions aligned to the new entity copy.
- Internal links added to `/how-soko-vibe-works`, `/soko-vibe-fees`, `/soko-vibe-escrow`; footer Soko column updated.

## F. Informational pages

- `/about` — org entity description, geo meta, BreadcrumbList JSON-LD, visible `.en` entity block, links to fee/escrow/how-it-works pages.
- `/about/founder` — same treatment; founder Person block remains linked into `Organization.founder` via `@id`.
- `/tanzania-marketplace` — long-form "Tanzania marketplace" page: entity description, geo, breadcrumb, visible entity text.
- `/how-soko-vibe-works` (NEW) — step-by-step buy/sell flow described with schema graph (Organization/WebSite/Person/BreadcrumbList) + geo + full OG/Twitter tags.
- `/soko-vibe-fees` (NEW) — factual fees only, taken from code/site copy: listings free; **3.5% platform fee charged to the buyer** (`server/src/config/index.js`, `platformCommissionPercent = 0.035`), seller receives the full selling price; wallet payout free; Boost pricing exactly as published on the homepage (Bronze TSh 1,500 / 3 days · Silver TSh 3,000 / 7 days · Gold TSh 10,000 / 30 days).
- `/soko-vibe-escrow` (NEW) — escrow via ClickPesa; mobile money (M‑Pesa, Tigo Pesa, Airtel Money, HaloPesa, EzyPesa); OTP order confirmation; disputes resolved within 14 days; seller KYC verification required. No accuracy-risk claims added beyond what the product publishes.

## G. Categories page (`/categories`)

Kept a public content page (instead of phantom product URLs that would return 404). Each of the 11 categories (Electronics, Fashion, Home & Garden, Automotive, Health & Beauty, Sports & Entertainment, Business & Industrial, Food & Beverages, Maternal & Kids, Services, Others) now has a factual Swahili description grounded in the real subcategory names, plus the org entity, geo, breadcrumb, and internal links.

> Note: individual product/seller URLs do not exist yet (native-app catalog). We do **not** fabricate them. When the public catalog ships, generate URL per product/seller and switch the sitemap to an index (see K, T).

## H. Legal & support pages

`/privacy-policy`, `/terms-of-service`, `/support` use the legacy template (`styles.css` + `i18n.js`/`legal_i18n.js`, runtime-injected text). Changes:
- Added favicon links and full `og:image` (with width/height/alt) + `twitter:card/title/description/image`.
- Added a compact **Organization** JSON-LD block (with the official description) so entity identity is consistent even on legal pages.
- Removed a previously-placed `twitter:site @sokovibe` — that handle was not verified and we do not invent social handles.
- Legal page *content* is untouched (correctness of policy text is the owner's responsibility).

## I. Structured data architecture

Every public page now carries an `application/ld+json` graph and all pages pass a graph-edge check (`server/scripts/seo-jsonld-check.js`):

- **Organization** (`#organization`) — name, url, description, email, telephone, `address` (Dar es Salaam, TZ), `areaServed` (Tanzania), `founder` → `#founder`. Present on every page (including legal pages).
- **WebSite** (`#website`) — `publisher` → `#organization`.
- **Person** (`#founder`) — the founder page person, present on the 8 modern pages as available in site content.
- **BreadcrumbList** — on every inner page (7), intentionally absent on root.
- **FAQPage** — homepage only.

Verifier output (local):
```
ALL JSON-LD CHECKS PASSED
PASS JSON-LD parses on all pages
PASS one consistent Organization entity on every page
PASS consistent WebSite entity (#website) on every page
PASS consistent Person entity (#founder) on 8 pages
PASS @id graph edges correct (website→org, person→org, org→person)
PASS Organization description identical on every page
PASS BreadcrumbList on all inner pages (7), absent on root as expected
PASS FAQPage present on homepage only (1 page)
```

## J. Geo targeting

- `geo.region` = `TZ` and `geo.placename` = `Dar es Salaam, Tanzania` meta tags on all modern pages.
- JSON-LD `address.addressCountry` = `TZ`, `addressLocality` = `Dar es Salaam`, `areaServed` = Tanzania on the Organization block.
- Content states "Tanzania-based / Tanzania online marketplace" in title, description, H1 and body — strong local-relevance signal without fake location schemes.

## K. Sitemap

`sitemap.xml` now lists 11 URLs (all confirmed 200 in checks):
`/`, `/tanzania-marketplace`, `/categories`, `/how-soko-vibe-works`, `/soko-vibe-fees`, `/soko-vibe-escrow`, `/about`, `/about/founder`, `/privacy-policy`, `/terms-of-service`, `/support`.

A code comment marks the migration point: when product/category/seller web pages exist, switch to a `<sitemapindex>` with `pages.xml` + generated `categories.xml`/`products.xml`/`sellers.xml` + `lastmod`. (The `loc` host is the canonical `www.sokovibe.co.tz`.)

## L. robots.txt

Serves `text/plain` at `/robots.txt` with `Sitemap: https://www.sokovibe.co.tz/sitemap.xml` and:

```
User-agent: *
Disallow: /api/
Disallow: /apiv1/
Disallow: /admin/
Disallow: /health
Disallow: /marketing/
Disallow: /product-fallback.html
Disallow: /dashboard
Disallow: /account
Disallow: /checkout
Disallow: /auth/
Disallow: /signin
Disallow: /signup
Disallow: /login
```

Private/financial surfaces are excluded; all indexable public pages stay crawlable. `Disallow: /api/` is **unsafe** to remove while GET endpoints may expose PII — revisit when an authenticated API pass is complete.

## M. Canonicalization & redirects

- **Apex → www**: existing canonical redirect in `app.js` preserved (apex host redirects to `www.sokovibe.co.tz`).
- **HTTP → HTTPS**: new 301 fold for any request on the site host served over plain HTTP (`headers['Host']` ends with the domain), so there is a single HTTPS origin.
- **Trailing slash → 301**: `//`-safe collapse of `/path/` → `/path` (canonical URLs have no trailing slash) while exempting `/api`, `/health`, and `/.well-known`.
- **404 page**: single HTML 404 (noindex, canonical to home) now links users to `/`, `/categories`, `/tanzania-marketplace`, `/how-soko-vibe-works`, `/support` — a 404 that recovers sessions and passes a "no soft-404" check.

## N. Headers & caching

Verified by `seo-check.js`: `X-Content-Type-Options: nosniff`, `Strict-Transport-Security`, and `X-Frame-Options` are emitted on static responses; landing HTML is served fresh while `css/site.css`, `js/site.js` and images are cache-friendly. No user-supplied content reaches these headers (no SSRF/reflection vectors introduced).

## O. Social & icon tags

- Every modern page: `og:type=website`, title/description aligned with entity copy, `og:image` absolute URL with `width`/`height`/`alt`, `twitter:card=summary_large_image`, `twitter:title/description/image/image:alt`. Legal pages carry the same (card tuned to `summary`).
- Verified icon set already live at the origin: `apple-touch-icon.png`, `favicon-16x16.png`, `favicon-32x32.png`, `favicon.ico`, `favicon.png`, `icon-192.png`, `icon-512.png` + `manifest.json`; Apple touch/`manifest` links re-checked on pages touched. Legal pages now reference the same favicons.

## P. Internal linking

- Homepage → `how-soko-vibe-works`, `soko-vibe-fees`, `soko-vibe-escrow`, `tanzania-marketplace`, `categories`, `about`.
- Each new/informational page → the other two + `categories` + `tanzania-marketplace` (+ footer legal/support links), so every page is reachable from the home page in ≤2 clicks and there are no orphan URLs.

## Q. Verification & test suite

Local run against `http://localhost:3999` (server booted with `PORT=3999`):

```
node scripts/seo-check.js          → 110 passed, 0 failed
node scripts/seo-jsonld-check.js   → ALL JSON-LD CHECKS PASSED (exit 0)
npm test                           → 104 pass / 33 fail (ALL 33 failures are pre-existing
                                     e2e.live.test.js cases that target the deployed
                                     Render API soko-langu-server.onrender.com and 404 on
                                     legacy /api endpoints no longer mounted there —
                                     unrelated to these changes)
```

Check highlights covered: homepage title/description/H1/entity statement, 200s + correct canonical for every public page, org entity text on every page, breadcrumbs on inner pages, trailing-slash 301, sitemap completeness, robots disallows, HSTS/security headers, asset availability, and the `Organization`/`WebSite`/`Person`/`FAQPage`/`BreadcrumbList` graph.

After deploy, re-run the same commands against the live origin:
```
cd server
$env:BASE_URL='https://www.sokovibe.co.tz'; node scripts/seo-check.js
$env:BASE_URL='https://www.sokovibe.co.tz'; node scripts/seo-jsonld-check.js
```

## R. Rollout: deploy + GSC/Bing verification + reindex

1. **Deploy**: commit & push `master` (push-to-deploy). Wait for the render build to finish.
2. **Live smoke**: curls for `/robots.txt`, `/sitemap.xml`, a 404, and apex→www + http→https 301s; then the two checks above against the live `BASE_URL`.
3. **Google Search Console**: verify `https://sokovibe.co.tz/` **and** `https://www.sokovibe.co.tz/` (follow the GSC host-verification flow; add GSC's provided DNS TXT or HTML tag — do not invent one). Submit `sitemap.xml`; use URL Inspection on `/`, `/categories`, and the three new pages → "Request Indexing".
4. **Bing Webmaster Tools**: verify both host forms too; submit `sitemap.xml`; enable automatic sitemap submission. Bing also ingests IndexNow (next section).
5. **Recheck in a week**: GSC "Coverage / Page indexing" and Rich Results for breadcrumb/FAQ; Search for "Soko Vibe" and ask whether the knowledge panel resolves the Tanzania-marketplace entity.

## S. IndexNow

- Server support is wired in `server/src/seo/routes.js`: when the environment variable `INDEXNOW_KEY` is set, the route `GET /{INDEXNOW_KEY}.txt` serves a plain-text key file. If the variable is absent the route is **not registered** (nothing leaks).
- Submission helper `server/scripts/indexnow-submit.js` (run from `server/`):
  1. Generate a 32-char lowercase hex key: `node -e "console.log(require('crypto').randomBytes(16).toString('hex'))"`.
  2. Set `INDEXNOW_KEY` in the deployed environment (Render dashboard env var) with that key.
  3. Submit current public URLs:
     ```
     $env:INDEXNOW_KEY='<your 32-hex key>'
     node scripts/indexnow-submit.js
     ```
     It POSTs only canonical `https://www.sokovibe.co.tz/<path>` URLs to `https://api.indexnow.org/indexnow`, prints per-URL HTTP results, and exits 0 on success — safe to run after every content deploy.
  4. Bing Webmaster Tools can also adopt the same key for its "IndexNow key" field; keep the key file permanently reachable at `/KEY.txt`.
- (Optional) set a cron/GitHub Action: on merge to `master`, `cd server && node scripts/indexnow-submit.js`.

## T. Expected impact & sequenced follow-ups

**Immediate**: consistent entity answers for "Soko Vibe", "Soko Vibe Tanzania", "Tanzania online marketplace" style queries; richer results (breadcrumbs, site links, possible Organization/knowledge-panel alignment); clean single-origin (apex/www + http/https + slash) signals; faster Bing/IndexNow‑based indexing; a recoverable 404.

**Sequenced roadmap (do not skip validation):**
1. When the public product/seller catalog ships: generate SEO URLs (e.g. `/product/<slug>`, `/seller/<slug>`), add `ItemList`/`Product`/`Seller` JSON-LD, switch sitemap to index, update internal links from the category page.
2. Once verified official social profiles exist, add the real profile URLs to `sameAs`.
3. If real separate per-language URLs are ever built, then and only then add `hreflang`.
4. `hosting/` legacy Firebase mirror remains off-path — either delete it or keep it in sync before it could ever be deployed to a hosting origin (a stale second copy at another origin would split the entity).
5. Keep `platformCommissionPercent` and boost prices in the fees page in sync with any pricing change (single-edit via README-noted constants when possible).