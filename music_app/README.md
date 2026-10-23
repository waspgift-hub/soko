# SokoVibe Music

Flutter music discovery and playback app for SokoVibe.

## Architecture

`Flutter app -> SokoVibe Music Cloudflare Worker -> Jamendo API`

The currently configured Worker URL is `https://soko-vibe-music-backend.wapalila.workers.dev`. The Cloudflare account has a Worker with this name and the `wapalila` workers.dev subdomain. This verifies the configured resource exists; the live API and actual audio playback still require smoke tests.

The Worker keeps the Jamendo client ID server-side and returns normalized track metadata, stream URLs, and download-permission metadata. The app must not assume every track is downloadable or that a stream URL grants offline rights.

The app also contains a lyrics service. Generated original lyrics, when available, are distinct from licensed lyrics for commercial recordings. Availability depends on the deployed Worker and provider configuration.

## Run locally

```bash
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=MUSIC_API_URL=https://soko-vibe-music-backend.wapalila.workers.dev
```

Set `MUSIC_API_URL` to the actual Worker URL for the environment being tested. Do not put provider credentials in Flutter configuration or commit secrets.

## Current app capabilities

- Search Jamendo music through the Worker with pagination.
- Resolve track metadata and an HTTPS stream URL immediately before playback.
- Display track title, artist, album artwork, duration, source, and license metadata when supplied.
- Request recommendations and original lyrics through the Worker where configured.
- Import and play local audio selected through Android's file picker without internet access for local files.
- Keep preferences locally, including theme/accent and listening-reminder settings.
- Material 3 interface, mini-player, and an in-app privacy policy.

The app currently does **not** include account creation, Google Sign-In, cloud-synced favorites/playlists/history, subscriptions, Google Play Billing, advertising SDKs, artist uploads, or a verified full background-media-control implementation. Do not advertise these as available until implemented and tested.

Availability of search, recommendations, streaming, lyrics, and downloads depends on the deployed backend, provider responses, account configuration, and applicable licenses. A successful build does not prove live playback works; verify Worker health, search results, HTTPS stream resolution, and actual audio playback separately.

## Download and licensing safeguards

The app only enables an offline download when the provider explicitly marks the track as downloadable and supplies a valid HTTPS download URL. Never treat a streaming URL as a download URL. Provider metadata is not, by itself, blanket permission for commercial redistribution, advertising, or monetization.

## Privacy

The app includes an in-app Privacy policy screen and a policy document at [PRIVACY_POLICY.md](PRIVACY_POLICY.md). Publish a stable public policy URL and keep the Google Play Data safety declaration consistent with the actual implementation and provider configuration before release.

## Android build and CI

The `.github/workflows/flutter-music.yml` workflow:
- checks Worker JavaScript syntax;
- generates Android platform files for the current Flutter project;
- sets Android compile and target SDK to API 36;
- enables core-library desugaring required by notifications;
- resolves dependencies, runs static analysis and tests;
- builds an APK candidate with the configured Worker URL;
- checks the deployed Worker health and a real Jamendo search; and
- builds a Play Store AAB only when the owner-managed upload signing secrets are configured.

The APK candidate is for installation/testing and must not be assumed Play Store-ready. See [PLAY_STORE_RELEASE_CHECKLIST.md](PLAY_STORE_RELEASE_CHECKLIST.md) for signing, policy, store-listing, and testing requirements.

## Production status

The deployed Worker observed in Cloudflare is older than the current source in this repository. The current Cloudflare connection does not have Workers Scripts write permission, so deployment from this session was blocked. Do not claim the new source is deployed until a write-enabled deployment and successful smoke test are recorded.
