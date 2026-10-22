# SokoVibe Music Worker

This Worker backs the Flutter app with Jamendo's official track API.

## Required bindings

- `JAMENDO_CLIENT_ID`: Jamendo API client ID. Configure as a Cloudflare Worker secret/variable; never put it in Flutter code.
- `AI`: existing Cloudflare Workers AI binding used for original lyrics generation.

The Jamendo Client Secret is not needed for the public read-only track search endpoints in this Worker. Do not add it to the mobile app or source control. If it was exposed, rotate it in the Jamendo developer dashboard.

## Endpoints

- `GET /api/health`: reports whether Jamendo can be reached; status is `healthy` only after a live provider request succeeds.
- `GET /search?q=afrobeat`: searches Jamendo and returns `results` with `id`, `title`, `artist`, `image`, `streaming_url`, `duration`, and `license`.
- `GET /play/{trackId}`: resolves a track to its Jamendo audio URL.
- `POST /api/search`: JSON body `{"query":"afrobeat"}`, backed by Jamendo.
- `POST /api/recommend`: returns Jamendo tracks filtered by genre/mood/language.
- `POST /api/lyrics`: generates original lyrics using the existing Workers AI binding.

## Deploy

Upload `worker.js` to the existing Cloudflare Worker named `soko-vibe-music-backend`, preserving its existing `AI` binding, then configure `JAMENDO_CLIENT_ID` as a Worker secret. With Wrangler, run from this directory:

```sh
npx wrangler secret put JAMENDO_CLIENT_ID
npx wrangler deploy
```

After deployment, verify:

```sh
curl -i https://soko-vibe-music-backend.sokovibe-co-tz.workers.dev/api/health
curl -i 'https://soko-vibe-music-backend.sokovibe-co-tz.workers.dev/search?q=afrobeat'
```

Do not mark the integration connected until the health endpoint reports `jamendo.status=connected` and search returns real track records.
