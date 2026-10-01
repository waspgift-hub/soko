import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/services/youtube_search_service.dart';

void main() {
  group('parseYouTubeResults', () {
    test('maps server items to videos', () {
      final out = parseYouTubeResults({
        'success': true,
        'items': [
          {
            'videoId': 'abc123XYZ_-',
            'title': 'Song One',
            'channel': 'Channel A',
            'thumbnail': 'https://img/mq.jpg',
            'publishedAt': '2024-01-01T00:00:00Z',
          },
          {'videoId': '', 'title': 'Skipped: no id'},
        ],
      });
      expect(out.length, 1);
      expect(out.first.videoId, 'abc123XYZ_-');
      expect(out.first.title, 'Song One');
      expect(
        out.first.watchUrl,
        'https://www.youtube.com/watch?v=abc123XYZ_-',
      );
    });

    test('tolerates garbage payloads', () {
      expect(parseYouTubeResults(null), isEmpty);
      expect(parseYouTubeResults({}), isEmpty);
      expect(parseYouTubeResults({'items': 'nope'}), isEmpty);
      expect(parseYouTubeResults({'items': []}), isEmpty);
    });
  });
}
