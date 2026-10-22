# Soko Vibe Music

Flutter music discovery/player app for Soko Vibe.

## Architecture

`Flutter app -> Soko Vibe Music API (Cloudflare Worker) -> Audiomack API`

Lyrics are looked up separately through the public LRCLIB API. The app requests an exact match first, then searches by title and artist. It supports plain lyrics and LRC timestamped lyrics when available.

The Flutter APK must never contain Audiomack OAuth consumer secrets. The Worker is the server-side boundary for API credentials and short-lived playback URLs.

## Run

```bash
flutter pub get
flutter analyze
flutter run --dart-define=MUSIC_API_URL=https://your-worker.example.workers.dev
```

## Current features

- Search songs, artists and albums through the v2 backend with page/limit parameters.
- Load mood/genre/language recommendations through the backend.
- Generate original lyrics with the backend's Workers AI endpoint.
- Run live health, search, playback-resolution and recommendation checks from the diagnostics screen; AI lyrics can be tested separately to avoid unnecessary AI usage.
- Cover art, title and artist display.
- Tap play to request a fresh streaming URL.
- Lyrics button for each result.
- Plain lyrics and timestamped lyrics with playback-position highlighting when synced lyrics are available.
- Lyrics retry/error states and instrumental-track handling.
- Persistent app settings: system/light/dark theme, accent colour, daily reminder toggle and configurable reminder time.
- Daily listening reminder and important local notifications.
- Material 3 UI and bottom mini-player with play/pause.

Lyrics availability depends on LRCLIB's catalogue and metadata matching; not every song will have lyrics. The app sends the song title and artist to LRCLIB for lookup, not the audio stream. The lyrics provider may rate-limit requests, so the app shows a retry message instead of repeatedly retrying automatically.

Audiomack's documented streaming URL is short-lived, so the app requests `/play/:id` immediately before playback instead of caching the URL. See the official Audiomack API documentation: https://audiomack.com/data-api/docs

Lyrics API documentation: https://lrclib.net/docs
