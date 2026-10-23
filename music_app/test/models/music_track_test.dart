import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe_music/models/music_track.dart';

void main() {
  group('MusicTrack.fromJson', () {
    test('maps Jamendo response fields used by search and offline library', () {
      final track = MusicTrack.fromJson(<String, dynamic>{
        'id': 12345,
        'title': 'Example track',
        'artist': 'Example artist',
        'image': 'https://example.com/cover.jpg',
        'streaming_url': 'https://example.com/audio.mp3',
        'duration': 187,
        'license': 'https://creativecommons.org/licenses/by/4.0/',
      });

      expect(track.id, '12345');
      expect(track.title, 'Example track');
      expect(track.artist, 'Example artist');
      expect(track.image, 'https://example.com/cover.jpg');
      expect(track.streamUrl, 'https://example.com/audio.mp3');
      expect(track.durationSeconds, 187);
      expect(track.license, 'https://creativecommons.org/licenses/by/4.0/');
    });

    test('uses safe defaults for missing optional fields', () {
      final track = MusicTrack.fromJson(<String, dynamic>{});

      expect(track.id, '');
      expect(track.title, 'Unknown title');
      expect(track.artist, 'Unknown artist');
      expect(track.image, '');
      expect(track.license, '');
      expect(track.durationSeconds, 0);
    });
  });
}