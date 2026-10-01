import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/services/youtube_utils.dart';

void main() {
  group('youTubeIdFromUrl', () {
    test('parses watch URLs', () {
      expect(
        youTubeIdFromUrl('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
    });

    test('parses watch URLs with extra params', () {
      expect(
        youTubeIdFromUrl(
          'https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42s&list=PL123',
        ),
        'dQw4w9WgXcQ',
      );
    });

    test('parses youtu.be links', () {
      expect(
        youTubeIdFromUrl('https://youtu.be/dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
    });

    test('parses shorts, live and embed paths', () {
      expect(
        youTubeIdFromUrl('https://www.youtube.com/shorts/dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
      expect(
        youTubeIdFromUrl('https://m.youtube.com/live/dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
      expect(
        youTubeIdFromUrl('https://www.youtube.com/embed/dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
    });

    test('rejects non-YouTube and malformed URLs', () {
      expect(youTubeIdFromUrl('https://example.com/video.mp4'), isNull);
      expect(youTubeIdFromUrl('https://www.youtube.com/watch?v=short'), isNull);
      expect(youTubeIdFromUrl('https://www.youtube.com/'), isNull);
      expect(youTubeIdFromUrl('not a url at all'), isNull);
      expect(youTubeIdFromUrl(''), isNull);
    });

    test('isYouTubeUrl mirrors the parser', () {
      expect(isYouTubeUrl('https://youtu.be/dQw4w9WgXcQ'), isTrue);
      expect(isYouTubeUrl('https://example.com/a.mp4'), isFalse);
    });

    test('embed URL uses the nocookie domain with autoplay', () {
      final embed = youTubeEmbedUrl('dQw4w9WgXcQ');
      expect(embed.contains('youtube-nocookie.com/embed/dQw4w9WgXcQ'), isTrue);
      expect(embed.contains('autoplay=1'), isTrue);
    });
  });
}
