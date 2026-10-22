# SokoVibe Music API

Cloudflare Worker API for the SokoVibe Music Flutter app. This initial provider adapter uses the official Jamendo API for music search and playable URLs.

## Endpoints

- `GET /health` — health check; does not verify provider credentials.
- `GET /search?q=afrobeat` — search tracks.
- `GET /play/{trackId}` — resolve a track's Jamendo audio URL.

Search response follows the Flutter app's model:

```json
{
  "results": [
    {
      "id": "track-id",
      "title": "Track title",
      "artist": "Artist name",
      "image": "https://...",
      "streaming_url": "https://...",
      "duration": 180,
      "license": "https://creativecommons.org/...",
      "source": "Jamendo"
    }
  ],
  "count": 1,
  "source": "Jamendo"
}
```

Example play response:

```json
{
  "id": "track-id",
  "streaming_url": "https://...",
  "source": "Jamendo",
  "license": "https://creativecommons.org/..."
}
```

## Deploy

1. Create/choose a Cloudflare account and obtain a Jamendo API client ID from the official Jamendo developer portal.
2. Install Wrangler and authenticate: `npx wrangler login`.
3. From this directory, set the credential as a Worker secret (do not commit it):
   `npx wrangler secret put JAMENDO_CLIENT_ID`
4. Deploy: `npx wrangler deploy`.
5. Wrangler prints the actual deployed URL, normally `https://sokovibe-music-api.<your-account-subdomain>.workers.dev`.
6. Test `/health`, then `/search?q=afrobeat`. A healthy endpoint alone does not prove the Jamendo credential works.

## Configure Flutter

Pass the real deployed URL when launching/building Flutter:

```sh
flutter run --dart-define=MUSIC_API_URL=https://YOUR-DEPLOYED-WORKER-URL
```

Or update the app's configured default after deployment. Never put a provider secret in Flutter code or in a public repository.

## Notes

- This service only returns catalog entries and provider audio URLs; it does not download or rehost audio.
- Playback and offline downloads must follow the track's license and Jamendo terms. Do not offer unrestricted downloads unless the provider explicitly permits them.
- This first version supports Jamendo only. Add other licensed providers through separate adapters.
- Rate limits, provider outages, and invalid credentials return a generic upstream error without exposing secrets.
