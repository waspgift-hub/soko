# SokoVibe Music Backend

Cloudflare Worker for the SokoVibe Music Flutter app. The deployed backend uses Jamendo for catalog search and playback, and Cloudflare Workers AI for optional recommendations/lyrics generation.

## Live service

- Base URL: `https://soko-vibe-music-backend.wapalila.workers.dev`
- `GET /` — service/version and endpoint list.
- `GET /api/health` — checks whether the Jamendo credential is configured and the provider can be reached.
- `GET /search?q=afrobeat` — searches tracks and returns cover art, title, artist, streaming URL and license/download metadata.
- `GET /play/{trackId}` — resolves a fresh playable URL and returns the track under the `track` property.
- `GET /download/{trackId}` — redirects only when Jamendo confirms that the track is downloadable under its license.
- `POST /api/search` — JSON search alternative.
- `POST /api/recommend` — mood/genre recommendations.
- `POST /api/lyrics` — lyrics assistance when the AI binding is configured.

## Required bindings

- `JAMENDO_CLIENT_ID` — set as a Cloudflare Worker secret. Never commit the value.
- `AI` — Cloudflare Workers AI binding, used by optional recommendation/lyrics routes.

## Deploy

Run from this directory after authenticating Wrangler:

```sh
npx wrangler login
npx wrangler secret put JAMENDO_CLIENT_ID
npx wrangler deploy
```

The Worker configuration targets `soko-vibe-music-backend`. The deployed secret is managed separately from source. If deploying to a new account, configure the `AI` binding and set the secret in that account before expecting live catalog results.

## Configure Flutter

The app defaults to this Worker. For another environment, pass the base URL at build/run time:

```sh
flutter run --dart-define=MUSIC_API_URL=https://YOUR-WORKER-URL
```

## Licensing and offline playback

The Worker returns Jamendo's `audiodownload` URL and `audiodownload_allowed` flag. The app enables downloads only when the provider explicitly marks the track as downloadable, and it stores downloaded files in the app's private documents directory. Streaming URLs are resolved when needed and are not treated as permanent download URLs.

The CI workflow builds a release APK, optionally deploys the Worker when the `CLOUDFLARE_API_TOKEN` GitHub Actions secret is configured, and smoke-tests health, live search, playback metadata, and licensed-download behavior against the live Worker. The token must have Cloudflare Workers Scripts edit/write permissions. A successful build does not replace manual playback checks on a physical Android device.
