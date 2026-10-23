# SokoVibe Music

Flutter music discovery and playback app for SokoVibe.

## Architecture

`Flutter app -> SokoVibe Music Cloudflare Worker -> Jamendo API`

The Worker keeps the Jamendo client ID server-side and returns normalized track metadata, stream URLs, and explicit download-permission metadata. The app must not assume every track is downloadable or that a stream URL grants offline rights.

The app also contains a lyrics service. Lyrics availability depends on the configured provider and its catalogue; generated lyrics, if enabled on the deployed Worker, are distinct from licensed lyrics for commercial recordings.

## Run locally

```bash
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=MUSIC_API_URL=https://your-worker.example.workers.dev
```

Set `MUSIC_API_URL` to the actual deployed Worker URL for the environment being tested. Do not put provider credentials in Flutter configuration or commit secrets.

## Current app capabilities

- Search music through the Worker with pagination.
- Resolve track metadata and an HTTPS stream URL immediately before playback.
- Display track title, artist, album artwork, duration, source, and license metadata when supplied.
- Request recommendations through the Worker where configured.
- Request lyrics through the configured lyrics service where available.
- Play local audio selected from the Android file picker, without internet access for those local files.
- Store user preferences locally, including theme/accent and listening-reminder settings.
- Material 3 interface and a mini-player.

Availability of search, recommendations, streaming, lyrics, and downloads depends on the deployed backend, provider responses, account configuration, and applicable licenses. A successful build does not prove live playback works; verify the deployed Worker health, search response, resolved stream URL, and actual audio playback separately.

## Download and licensing safeguards

The app must only enable a download when the provider explicitly marks the track as downloadable and supplies a valid download URL. Never treat a streaming URL as a download URL. Provider metadata is not, by itself, legal advice or blanket permission for commercial redistribution or monetization.

## Android build and CI

The repository's `.github/workflows/flutter-music.yml` workflow checks Worker JavaScript syntax, resolves Flutter dependencies, runs static analysis and tests, builds a release APK, verifies that the artifact is non-empty, and uploads it as a GitHub Actions artifact.

Google Sign-In requires the Android app to be registered in Firebase, Google as an enabled Authentication provider, matching signing fingerprints, and the appropriate Firebase Android configuration. Until these are supplied and runtime-tested, Google authentication must be treated as unverified.
