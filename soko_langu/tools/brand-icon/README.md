# Soko Vibe brand icon

Every icon in the product — Android launcher, iOS AppIcon, notification small
icon, PWA manifest icons, favicons, and the website wordmark — is generated from
one vector trace of the "SV" mark. This directory is the source of truth for the
mark; nothing under `assets/`, `android/`, `ios/`, `web/` or `hosting/` should be
hand-edited as an icon.

## Why it is scripted

The notification small icon and the Android adaptive-icon foreground have to be
*vectors*, not images. A 24dp notification icon cannot be produced from a
downscaled PNG without the counters filling in, and a raster adaptive foreground
blurs on every launcher mask. So the mark is traced once and emitted as
`pathData`.

## Usage

```bash
cd tools/brand-icon
npm install
npm run build        # trace + write every icon into the repo
```

| Script | What it does |
|---|---|
| `npm run trace` | `src/soko_vibe_mark_1920.png` -> `master.json` (normalised SVG path) |
| `npm run generate` | `master.json` -> all raster + VectorDrawable outputs |
| `npm run qa` | Contact sheet of every fit at true device size, vs. the source |
| `npm run qa:sizes` | Legibility sweep for the notification and favicon sizes |
| `npm run qa:masks` | Adaptive/maskable icons under real launcher mask shapes |

`qa*.js` write `qa.png` into this directory. Open it after any change to `FIT`
in `trace.js` — the notification and favicon sizes are the ones that fail
silently.

## Changing the mark

1. Replace `src/soko_vibe_mark_1920.png`. Transparent background, square canvas.
2. Adjust `FIT` in `trace.js` only if the new proportions need it.
3. `npm run build`, then `npm run qa`, `npm run qa:sizes`, `npm run qa:masks`.
4. Commit `master.json` and the regenerated icons together.

`trace.js` asserts the traced ink aspect is between 1.10 and 1.35. A trace that
lands outside that range means the background was picked up instead of the glyph
(ink is on the *light* side of the threshold — see `blackOnWhite` in `trace.js`),
not that the artwork changed.

## Conventions

| Surface | Background | Mark | Fit |
|---|---|---|---|
| Android / iOS launcher | white | black | `icon` (56% width) |
| Android splash | white tile on black | black | `icon` |
| Notification small icon | none (silhouette) | white | `notification` (80%) |
| PWA + website favicon | black | white | `favicon` / `faviconSmall` |
| Website wordmark | black | white | `icon` |

The launcher icon is black-on-white so it matches the artwork already shipped and
the apparent icon size on the home screen does not change. Notifications and web
assets are white-on-black to match `web/manifest.json` and the black status bar.

`FIT.adaptiveFg` keeps the mark's bounding box inside the central 72/108dp that
Android guarantees is un-masked; `FIT.maskable` keeps it inside the inner 80%
that the PWA maskable spec guarantees.

## What is generated where

| Output | Notes |
|---|---|
| `assets/icons/app_icon_full.png` | `flutter_launcher_icons` source (pubspec.yaml) |
| `assets/app_icon.png` | in-app logo, used by the auth/home/receipt screens |
| `assets/icons/ic_foreground.png`, `ic_monochrome.png` | raster reference only — the shipped adaptive layers are vectors, so nothing consumes these |
| `res/drawable/ic_notification.xml` | VectorDrawable, 24dp. Also referenced by the manifest `flutter_notification_icon` and FCM meta-data, and by `android_icon` in the OneSignal payloads on the server |
| `res/drawable/ic_launcher_{foreground,monochrome}.xml` | VectorDrawable, 108dp |
| `res/mipmap-anydpi-v26/ic_launcher*.xml` | adaptive icon; background comes from `@color/ic_launcher_background` |
| `res/drawable*/launch_image.png` | splash mark, one density bucket each because `launch_background.xml` centres it at its intrinsic 96dp |
| `web/`, `hosting/`, `public/` | favicons, apple-touch-icon, PWA icons, `favicon.svg` |

`android_*/mipmap-*/ic_launcher*.png` and the iOS `AppIcon.appiconset` are **not**
written here — run `flutter pub run flutter_launcher_icons` after `npm run build`.

Renaming the notification drawable would require updating, together:
`AndroidManifest.xml` (`flutter_notification_icon`, FCM `default_notification_icon`),
`ConversationNotificationHelper.kt`, `local_notification_service.dart`, and the
`android_icon` / `small_icon` / `large_icon` fields in the server's OneSignal
payloads.

## Layout of this directory

```
src/soko_vibe_mark_1920.png  original artwork (transparent, square)
trace.js                     potrace -> master.json
svg.js                       fit maths + SVG builders shared by everything else
generate.js                  writes every icon into the repo
qa.js / maskqa.js            visual verification sheets
master.json                  generated: normalised path + per-fit geometry
```

`qa.png` and `.work.png` are gitignored.