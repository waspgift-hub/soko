# TODO - Soko Vibe fixes

## Priority 1: Music notifications (tray + lock screen)
- [x] Inspect and update `lib/services/audio_handler.dart` to integrate `just_audio_background`/proper background media notification behavior.
- [x] Ensure `MediaItem` artUri/title/artist propagate to lock-screen controls.

- [x] Update `lib/main.dart` / Android notification icon mapping to use `InShot_20260605_100643237.png` consistently.

- [x] Verify lock-screen controls: play/pause, next/previous; notification stays active during playback.
- [x] Verify notifications sound & visibility.

## Priority 2 (next after Priority 1): Flash sale banner + product cards
- [x] Fix flash sale banner rebuild/refresh behavior (`lib/widgets/flash_sale_banner.dart`).
- [x] Ensure flash-sale filtering uses current time and supports re-creating after expiry.
- [x] Verify `ProductCard` shows correct badge/discount after refresh.

## Other fixes (later)
- [x] Comment delete + permission error — already working (`comment_service.dart` validates userId ownership)
- [x] Mark all read in in-app notifications — already working (`notification_service.dart` batch update, `notification_screen.dart` has button)
- [x] Remove per-second loading in product details comments/rating — no such issue; `Timer.periodic` in `product_detail.dart` is only for flash sale countdown
- [x] Onboarding: language + phone number before create account — already implemented (onboarding collects lang + phone, then routes to account selection)
- [x] Offline mode for audio — `AudioCacheService` integrated into `MusicHandler._toSource()`; cached URLs resolved when available; service initialized eagerly in `main.dart`
