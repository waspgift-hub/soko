import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/services/profile_media_controller.dart';

void main() {
  group('ProfileMediaController queue math', () {
    test('nextIndex wraps around to the start', () {
      expect(ProfileMediaController.nextIndex(0, 3), 1);
      expect(ProfileMediaController.nextIndex(2, 3), 0);
    });

    test('previousIndex wraps around to the end', () {
      expect(ProfileMediaController.previousIndex(0, 3), 2);
      expect(ProfileMediaController.previousIndex(1, 3), 0);
    });

    test('empty queue stays at zero', () {
      expect(ProfileMediaController.nextIndex(0, 0), 0);
      expect(ProfileMediaController.previousIndex(0, 0), 0);
    });

    test('single item always points at itself', () {
      expect(ProfileMediaController.nextIndex(0, 1), 0);
      expect(ProfileMediaController.previousIndex(0, 1), 0);
    });
  });

  group('ProfileMediaController.nextIndexForMode', () {
    test('all wraps around the queue end', () {
      expect(
        ProfileMediaController.nextIndexForMode(2, 3, QueueRepeatMode.all),
        0,
      );
    });

    test('one pins the current item', () {
      expect(
        ProfileMediaController.nextIndexForMode(1, 3, QueueRepeatMode.one),
        1,
      );
    });

    test('off advances mid-queue but stops at the end', () {
      expect(
        ProfileMediaController.nextIndexForMode(0, 3, QueueRepeatMode.off),
        1,
      );
      expect(
        ProfileMediaController.nextIndexForMode(2, 3, QueueRepeatMode.off),
        2,
      );
    });

    test('empty queue stays at zero in every mode', () {
      for (final mode in QueueRepeatMode.values) {
        expect(ProfileMediaController.nextIndexForMode(0, 0, mode), 0);
      }
    });
  });

  group('ProfileMediaController.clampSeek', () {
    test('normal relative seek lands inside the duration', () {
      expect(
        ProfileMediaController.clampSeek(
          const Duration(seconds: 30),
          const Duration(seconds: 10),
          const Duration(minutes: 2),
        ),
        const Duration(seconds: 40),
      );
    });

    test('seeking before zero clamps to zero', () {
      expect(
        ProfileMediaController.clampSeek(
          const Duration(seconds: 3),
          const Duration(seconds: -10),
          const Duration(minutes: 2),
        ),
        Duration.zero,
      );
    });

    test('seeking past the end clamps to the duration', () {
      expect(
        ProfileMediaController.clampSeek(
          const Duration(minutes: 1, seconds: 55),
          const Duration(seconds: 10),
          const Duration(minutes: 2),
        ),
        const Duration(minutes: 2),
      );
    });
  });
}
