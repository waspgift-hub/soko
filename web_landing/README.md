# Soko Vibe — Coming Soon Landing (`web_landing`)

Flutter Web “Coming Soon / Early Access” page for `https://www.sokovibe.co.tz`. Email registrations post to the existing Node/Express server and are stored in Firestore (`landing_waitlist`).

## Local development
```powershell
cd web_landing
flutter pub get
flutter run -d chrome --dart-define=SOKO_API_BASE=https://soko-langu-server.onrender.com
```

## Tests / checks
```powershell
cd web_landing
flutter analyze --no-pub
flutter test --no-pub test/locale_parity_test.dart test/landing_smoke_test.dart
```

## Cloudflare Pages (static site)
Create a Cloudflare Pages project connected to this repo, or deploy the build output.

- **Root directory**: `web_landing`
- **Build command**: `if ! command -v flutter >/dev/null 2>&1; then git clone https://github.com/flutter/flutter.git -b stable --depth 1; fi && export PATH="$PATH:$PWD/flutter/bin" && flutter config --enable-web && flutter pub get && flutter build web --release --dart-define=SOKO_API_BASE=https://soko-langu-server.onrender.com`
- **Build output directory**: `build/web`
- **Environment variable (optional but recommended)**: if your build image caches Flutter, keep the command simple: `flutter build web --release --dart-define=SOKO_API_BASE=https://soko-langu-server.onrender.com`

`web/_headers` and `web/_redirects` are included in the build (SPA fallback + caching/security headers).

**Custom domain**: add `www.sokovibe.co.tz` in Cloudflare Pages → Custom domains. Keep DNS proxied through Cloudflare. Set apex `sokovibe.co.tz` to redirect to `www` (Cloudflare Redirect Rule / Page Rule) to match canonical URLs.

## Render (API)
The landing form calls `POST /api/v1/launch/subscribe` on the existing Render web service (`soko-langu-server`, see root `render.yaml`).

Deploy:
1. Push/merge the server changes (`soko_langu/server/src/modules/launch/*`, mount in `src/app.js`).
2. In Render, redeploy `soko-langu-server`.
3. Confirm required env vars are present (already used by the server): Firebase Admin credentials, `ADMIN_SECRET`, SMTP vars if using broadcast mail, and `ALLOWED_ORIGINS` must include `https://www.sokovibe.co.tz` and `https://sokovibe.co.tz`.

**Admin access (protected, not public):**
- `GET /api/v1/launch/subscribers?q=&limit=` — header `x-admin-secret: <ADMIN_SECRET>`
- `GET /api/v1/launch/subscribers/export` — CSV export, same header
- Existing admin panel/landing routes continue to read `landing_waitlist`.

## Notes
- Never expose Firebase credentials, `ADMIN_SECRET`, or database secrets in frontend code.
- Hosting/domain access is required to complete DNS/cutover; verify the live form end-to-end after deploy (submit → Firestore `landing_waitlist` → admin list/export).
