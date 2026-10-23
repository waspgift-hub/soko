import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe_music/services/offline_music_service.dart';

void main() {
  group('OfflineTrack', () {
    const track = OfflineTrack(
      id: 'local_song_1',
      title: 'My phone song',
      artist: 'Local music',
      path: '/app/offline_music/song.mp3',
      source: 'Device',
      license: '',
    );

    test('serializes and restores local file metadata', () {
      final restored = OfflineTrack.fromJson(track.toJson());

      expect(restored.id, track.id);
      expect(restored.title, track.title);
      expect(restored.artist, track.artist);
      expect(restored.path, track.path);
      expect(restored.source, 'Device');
      expect(restored.license, isEmpty);
    });

    test('restores safe defaults for incomplete stored metadata', () {
      final restored = OfflineTrack.fromJson(<String, dynamic>{});

      expect(restored.id, isEmpty);
      expect(restored.title, 'Unknown track');
      expect(restored.artist, 'Unknown artist');
      expect(restored.path, isEmpty);
      expect(restored.source, 'Device');
    });
  });
}
