# Soko Vibe Music

Flutter music discovery/player app for Soko Vibe.

## Architecture

`Flutter app -> Soko Vibe Music API (Cloudflare Worker) -> Audiomack API`

The Flutter APK must never contain Audiomack OAuth consumer secrets. The Worker is the server-side boundary for API credentials and short-lived playback URLs.

## Run

```bash
flutter pub get
flutter run --dart-define=MUSIC_API_URL=https://your-worker.example.workers.dev
```

## Current features

- Search songs, artists and albums through the backend.
- Cover art, title and artist display.
- Tap play to request a fresh streaming URL.
- Material 3 UI.
- Bottom mini-player with play/pause.

Audiomack's documented streaming URL is short-lived, so the app requests `/play/:id` immediately before playback instead of caching the URL. See the official Audiomack API documentation: https://audiomack.com/data-api/docs
