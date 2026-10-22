# Soko Vibe Music

Flutter music discovery/player app for Soko Vibe.

## Architecture

`Flutter app -> SokoVibe Music API (Cloudflare Worker) -> Jamendo API`

Lyrics are looked up separately through the public LRCLIB API. The app requests an exact match first, then searches by title and artist. It supports plain lyrics and LRC timestamped lyrics when available.

The Flutter APK never contains the Jamendo client ID as a secret. The Worker keeps the provider credential server-side and requests a fresh playback URL when needed.

## Run

```bash
flutter pub get
flutter analyze
flutter run --dart-define=MUSIC_API_URL=https://your-worker.example.workers.dev
```

## Current features

- Search songs, artists and albums through the backend.
- Cover art, title and artist display.
- Tap play to request a fresh streaming URL.
- Download songs to app-private storage and play saved files offline.
- Manage and delete downloaded tracks in the Downloads screen.
- Lyrics button for each result.
- Plain lyrics and timestamped lyrics with playback-position highlighting when synced lyrics are available.
- Lyrics retry/error states and instrumental-track handling.
- Persistent app settings: system/light/dark theme, accent colour, daily reminder toggle and configurable reminder time.
- Daily listening reminder and important local notifications.
- Material 3 UI and bottom mini-player with play/pause.

Lyrics availability depends on LRCLIB's catalogue and metadata matching; not every song will have lyrics. The app sends the song title and artist to LRCLIB for lookup, not the audio stream. The lyrics provider may rate-limit requests, so the app shows a retry message instead of repeatedly retrying automatically.

The app requests `/play/:id` immediately before playback rather than persisting temporary streaming URLs. Tracks can be downloaded to the app's private storage for offline listening; downloads are managed from the Downloads screen.

Lyrics API documentation: https://lrclib.net/docs


## Startup sound identity and Google sign-in

- The app generates a short, original futuristic sonic logo locally (no bundled audio file or network request). It plays at most once per app process when startup sound is enabled in **Settings → Sound identity**. Playback errors never block startup.
- The account action offers **Continue with Google** and **Continue as guest**. Guest mode does not require an account.
- Google sign-in uses Firebase Authentication. To activate it for a real Android install:
  1. Create/register the Android app in your Firebase project using the exact Android application ID from the Android Gradle configuration.
  2. Enable **Authentication → Sign-in method → Google** in Firebase Console.
  3. Add the app's SHA-1 and SHA-256 fingerprints to the Firebase Android app.
  4. Add the matching `google-services.json` at `android/app/google-services.json` and apply the Google Services Gradle plugin as required by the project's Android Gradle setup.
  5. Run `flutter pub get`, `flutter analyze`, and `flutter test` on a machine with Flutter/Android tooling.
- No Firebase project configuration or `google-services.json` is committed here. Until the project-specific setup is supplied, Google login reports a setup message instead of pretending authentication succeeded. Guest mode remains available.


### Build and validation notes

The `music_app` directory currently contains the Flutter source package but does not commit generated Android platform files. The Music CI workflow generates Android scaffolding on its runner, sets Android minSdk to 23 for Firebase compatibility, runs dependency resolution, Dart analysis and tests, and builds a debug APK artifact. That generated platform directory is temporary and is not added to this branch.

A successful APK compile does **not** prove Google sign-in works at runtime. Real Google authentication still requires a registered Firebase Android app, enabled Google provider, matching package ID and SHA fingerprints, `google-services.json`, and Google Services Gradle configuration. The CI debug APK is therefore a compile artifact, not a release-ready or Firebase-configured build.
