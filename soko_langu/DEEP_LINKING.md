# Soko Vibe — Deep Linking

## 1. How it works

Soko Vibe uses standard HTTPS deep links (Android App Links + iOS Universal
Links) — **no Firebase Dynamic Links**. Product links are shared as:

```
https://www.sokovibe.co.tz/product/{productId}
```

- **App installed** → the OS opens Soko Vibe and navigates straight to the
  product details screen via GoRouter.
- **App not installed** → the link lands on the **Flutter web app** running on
  `www.sokovibe.co.tz` (the web build is the root of the site, TikTok-style
  guest browsing). `/product/:id` and `/seller/:id` are served by the SPA
  history fallback, so the user sees the product page right in the browser.
  The old static `product-fallback.html` is retired.

Dart-side handling lives in `lib/services/deep_link_service.dart`:

1. `AppLinks.getInitialLink()` captures a cold-start link as early as possible.
2. `AppLinks.uriLinkStream.listen(...)` handles warm starts (app already
   running).
3. The URL is parsed (scheme + host allow-list + path) into an internal
   GoRouter location.
4. Navigation is deferred until the app signals initialization is complete
   (`AppStateNotifier.appInitialized`), so it can never race Firebase init,
   auth restore or the router redirects.
5. The shell navigates with `appRouter.go(location)`, which is a no-op when the
   target is already the current location (no duplicate product screens).

Product `{productId}` is not validated further on purpose: the existing
`/product/:id` GoRouter route already loads the document from Firestore and
shows loading / not-found states.

## 2. Supported URL formats

| External URL | Internal route | Screen |
| --- | --- | --- |
| `https://www.sokovibe.co.tz/product/{id}` | `/product/{id}` | Product details |
| `https://www.sokovibe.co.tz/seller/{id}` | `/public-profile/{id}` | Seller public profile |

Only these two paths are accepted. Any other host/path is ignored (the app
stays where it is). To add a route, extend `_toLocation()` in
`deep_link_service.dart` with a mapping to a real existing GoRouter route.

## 3. Android configuration

- `applicationId` / namespace: `com.sokolangu.app`
- Intent filter added to `android/app/src/main/AndroidManifest.xml` (inside the
  `MainActivity` activity) with `ACTION_VIEW` + `DEFAULT` + `BROWSABLE` and
  `android:autoVerify="true"` for hosts:
  - `www.sokovibe.co.tz` (pathPrefix `/product`, `/seller`)
  - `sokovibe.co.tz` (pathPrefix `/product`, `/seller`)
- Verification file: `https://www.sokovibe.co.tz/.well-known/assetlinks.json`

The `assetlinks.json` currently contains the **real** SHA-256 fingerprints read
from the project keystores:

- Release (`android/app/release-keystore.jks`):
  `381F259381F2F349DDB813E7BBD1FDC42ABF78A23BBCFBFE65D9B6B4E20CAF77`
- Debug (`~/.android/debug.keystore`):
  `4D0D74A02A3DEFEBC50EE84B22826A1E149EF02F57306ECDC318E80E19E91F2F`

> If the release keystore ever changes, regenerate with:
> `keytool -list -v -keystore release-keystore.jks -alias soko_vibe`

The apex host `sokovibe.co.tz` currently has **no valid TLS certificate** and
therefore cannot be auto-verified. It is harmless to keep it in the filter; the
`www` host works on its own. Fix DNS/TLS and the apex will verify too.

## 4. iOS configuration

- Bundle identifier: `com.example.sokoLangu` — still the Flutter template
  value. **Change to a real production bundle id before shipping to the App
  Store.**
- Associated Domains entitlement added to
  `ios/Runner/Runner.entitlements`:
  - `applinks:www.sokovibe.co.tz`
  - `applinks:sokovibe.co.tz`
- Verification file:
  `https://www.sokovibe.co.tz/.well-known/apple-app-site-association`

The AASA contains `REPLACE_WITH_ACTUAL_IOS_TEAM_ID.com.example.sokoLangu` because
the **Apple Team ID is not present anywhere in this repo** — it must be filled
in (with the real bundle id) before Universal Links can work.

> iOS builds cannot be validated on this Windows machine; build in Xcode and
> confirm `Signing & Capabilities → Associated Domains`.

## 5. Required domain configuration

| Item | Status |
| --- | --- |
| `www.sokovibe.co.tz` | Live today (verified 200/HTTPS), serves `.well-known` files |
| `sokovibe.co.tz` (apex) | No valid TLS cert — optional, add DNS + TLS to verify |
| `sokovibe.com` | **Not owned/configured by this project — not used** |

## 6. Required values to supply

- `REPLACE_WITH_ACTUAL_IOS_TEAM_ID` — from Apple Developer account.
- Real iOS bundle identifier (see §4).
- `ANDROID_STORE_URL` / `IOS_STORE_URL` server env vars — only once the app is
  actually listed on a store; empty today, so until then there are no bogus
  store buttons. `WEB_PRODUCT_URL` defaults to
  `https://www.sokovibe.co.tz/product/`.

## 7. How to test links

Android (Device or emulator, app installed):

```
adb shell am start -W -a android.intent.action.VIEW -d "https://www.sokovibe.co.tz/product/TEST_ID" com.sokolangu.app
```

- Verify association first: `adb shell pm list packages -d` (should not list
  the app) and after `adb install`, check
  `adb shell dumpsys package com.sokolangu.app | grep -A 20 "Domain verification"`.
- Cold start: force-stop the app, then tap a link in a browser/WhatsApp.
- Warm start: leave the app on Home, tap the same link.
- Logged out: tap a link (product + seller routes are public guest-mode routes).
- Invalid id / deleted product: the existing Firestore loader shows the
  app's not-found state.
- Malformed URL: `https://www.sokovibe.co.tz/abc` stays in the browser (not an
  app link); unknown in-app paths are ignored.

Web (no app installed), open in any browser:

- Open `https://www.sokovibe.co.tz/product/anything` — the Flutter web app
  loads and the product page opens directly (SPA history fallback).
- The marketing landing now lives at `https://www.sokovibe.co.tz/marketing`
  (legal pages: `/marketing/privacy.html`, `/marketing/terms.html`,
  `/marketing/support.html`).

## 8. How sharing generates product URLs

`ProductDetailPage._shareProduct()` appends
`DeepLinkService.productShareUrl(product.id)` (=
`https://www.sokovibe.co.tz/product/{id}`) to the share text. No Firestore
paths, API keys or user data are ever included in a share link.

## 9. Where files live

| File | Purpose |
| --- | --- |
| `lib/services/deep_link_service.dart` | Parse + queue HTTPS links |
| `lib/main.dart` | Wiring: `_setupDeepLinks`, `flushPending`, `_onDeepLink` |
| `lib/screens/home/product_detail.dart` | Share text includes product URL |
| `android/app/src/main/AndroidManifest.xml` | App Links intent filters |
| `ios/Runner/Runner.entitlements` | Associated Domains |
| `server/landing/.well-known/assetlinks.json` | Android verification file |
| `server/landing/.well-known/apple-app-site-association` | iOS verification file |
| `server/src/app.js` | Serves `.well-known/`, the landing page at the root, `/marketing` (301), `/admin` |
| `server/src/config/index.js` | `deepLink` env config (store URLs) |

## 10. Serving the web site

- **The Flutter web app is no longer served** (`soko_langu/build/web` was
  removed from git). The marketplace lives on the native Android/iOS apps.
- `server/src/app.js` serves the marketing landing site from
  `server/landing/` at the root: `index.html` + `css/site.css` +
  `js/site.js` + `assets/` + `manifest.json`. Legal pages are served on clean
  URLs (`/privacy-policy`, `/terms-of-service`, `/support`). `/marketing`
  301-redirects to `/`. `/admin` keeps its static mount.
- Web deep links (`/product/...`) now return a premium 404 — the native share
  text still emits `www.sokovibe.co.tz/product/{id}`; switch share URLs to the
  app scheme when store links are live.
- Canonical host is the **apex** `https://sokovibe.co.tz`; the app middleware
  301s `www.sokovibe.co.tz` → apex.
- Firebase Console: add `sokovibe.co.tz` (apex) to **Authentication → Settings
  → Authorized domains** if web sign-in is ever re-enabled.