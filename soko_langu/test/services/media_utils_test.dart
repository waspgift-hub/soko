import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/services/media_utils.dart';

void main() {
  group('isAudioUrl', () {
    test('detects common audio extensions', () {
      expect(isAudioUrl('https://cdn.example.com/a.mp3'), isTrue);
      expect(isAudioUrl('https://cdn.example.com/a.m4a'), isTrue);
      expect(isAudioUrl('https://cdn.example.com/a.aac'), isTrue);
      expect(isAudioUrl('https://cdn.example.com/a.ogg'), isTrue);
      expect(isAudioUrl('https://cdn.example.com/a.opus'), isTrue);
      expect(isAudioUrl('https://cdn.example.com/a.wav'), isTrue);
      expect(isAudioUrl('https://cdn.example.com/a.flac'), isTrue);
    });

    test('ignores query strings and casing', () {
      expect(
        isAudioUrl('https://cdn.example.com/a.MP3?alt=media&token=x'),
        isTrue,
      );
    });

    test('rejects video, images and extensionless URLs', () {
      expect(isAudioUrl('https://cdn.example.com/a.mp4'), isFalse);
      expect(isAudioUrl('https://cdn.example.com/a.jpg'), isFalse);
      expect(isAudioUrl('https://youtu.be/dQw4w9WgXcQ'), isFalse);
      expect(isAudioUrl('https://example.com/noextension'), isFalse);
      expect(isAudioUrl(''), isFalse);
    });
  });
}
