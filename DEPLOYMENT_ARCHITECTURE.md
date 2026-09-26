# Soko Vibe Deployment Architecture

## Production source of truth

- **GitHub**: source control and CI.
- **Flutter**: Android/iOS application. Web is built in CI for regression detection.
- **Cloudflare Pages**: public web deployment.
- **Cloudflare Worker**: API edge for `api.sokovibe.co.tz`.
- **Render**: authoritative Node.js/Express API origin.
- **Firebase**: Auth, Firestore, Storage and client SDK services; not web hosting and not backend compute.
- **PostgreSQL/Redis**: authoritative backend data and queues.
- **Cloudflare R2**: object/media storage where configured.

## Traffic

```
Web browser
  -> Cloudflare Pages
  -> public web

Flutter mobile app
  -> https://api.sokovibe.co.tz
  -> Cloudflare Worker
  -> Render Node/Express
  -> PostgreSQL / Redis / Firebase services
```

## CI

Pull requests run:
1. Flutter `pub get`
2. Flutter analyze
3. Flutter tests
4. Flutter Web release build
5. Node `npm ci`
6. Node lint
7. Node tests

Pushes to `main` run the same validation and then produce signed Android APK/AAB artifacts when the required signing secrets exist.

## Deployment boundaries

- GitHub Pages is **disabled as a production deployment target**.
- Firebase Hosting is **disabled as a production deployment target**.
- Firebase Cloud Functions are **not a production compute target** for this repository.
- Cloudflare Worker does **not** build Flutter Web.
- Render does **not** serve the Flutter application as the web deployment.
- `soko_langu/hosting/` is retained only as legacy/reference content and must not be treated as a live deployment source.

## Cloudflare Pages dashboard

The Pages project should point at this repository and use:
- Root directory: `soko_langu`
- Build command: `flutter build web --release --base-href /`
- Output directory: `build/web`

The exact Cloudflare project/domain settings are account-level configuration and are intentionally not stored as secrets in Git.

## Firestore deployment

Firebase remains authoritative for Firestore rules/indexes and Firebase client configuration. Changes to `firestore.rules` or `firestore.indexes.json` are deployed with Firebase CLI, not through a web-hosting workflow.

## Important rule

Do not add another hosting workflow for the same public web application. If the web provider changes later, update this document and the Cloudflare project configuration together, then keep GitHub CI as validation only.
