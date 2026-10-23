import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe_music/models/music_track.dart';

void main() {
  group('MusicTrack', () {
    test('maps Jamendo search fields and download permission', () {
      final track = MusicTrack.fromJson({
        'id': 123,
        'title': 'Test track',
        'artist': 'Test artist',
        'album': 'Test album',
        'image': 'https://cdn.example.test/cover.jpg',
        'streaming_url': 'https://cdn.example.test/stream.mp3',
        'audiodownload': 'https://cdn.example.test/download.mp3',
        'audiodownload_allowed': true,
        'license': 'https://creativecommons.org/licenses/by/4.0/',
        'duration': 123,
        'source': 'jamendo',
      });

      expect(track.id, '123');
      expect(track.title, 'Test track');
      expect(track.album, 'Test album');
      expect(track.artistAlbumLabel, 'Test artist • Test album');
      expect(track.canStream, isTrue);
      expect(track.canDownload, isTrue);
      expect(track.durationSeconds, 123);
    });

    test('does not allow download without explicit permission', () {
      final track = MusicTrack.fromJson({
        'id': '123',
        'title': 'Test track',
        'artist': 'Test artist',
        'streaming_url': 'https://cdn.example.test/stream.mp3',
        'audiodownload': 'https://cdn.example.test/download.mp3',
        'audiodownload_allowed': false,
      });

      expect(track.canStream, isTrue);
      expect(track.canDownload, isFalse);
    });

    test('rejects non-HTTPS streaming and download URLs', () {
      final track = MusicTrack.fromJson({
        'id': '123',
        'streaming_url': 'http://example.test/stream.mp3',
        'audiodownload': 'javascript:alert(1)',
        'audiodownload_allowed': true,
      });

      expect(track.canStream, isFalse);
      expect(track.canDownload, isFalse);
    });

    test('round trips local saved metadata without enabling downloads', () {
      final track = MusicTrack.fromLocalJson({
        'id': 'local_1',
        'title': 'My file',
        'artist': 'Local music',
        'license': '',
        'durationSeconds': 10,
        'source': 'local',
      });
      final restored = MusicTrack.fromLocalJson(track.toJson());

      expect(restored.id, 'local_1');
      expect(restored.isLocal, isTrue);
      expect(restored.canDownload, isFalse);
    });
  });
}
