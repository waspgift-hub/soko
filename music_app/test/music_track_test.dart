import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe_music/models/music_track.dart';

void main() {
  group('MusicTrack.fromJson', () {
    test('parses normalized Worker response fields', () {
      final track = MusicTrack.fromJson({
        'id': '123',
        'title': 'Test Song',
        'artist': 'Test Artist',
        'image': 'https://example.com/cover.jpg',
        'streaming_url': 'https://example.com/audio.mp3',
      });

      expect(track.id, '123');
      expect(track.title, 'Test Song');
      expect(track.artist, 'Test Artist');
      expect(track.image, 'https://example.com/cover.jpg');
      expect(track.streamUrl, 'https://example.com/audio.mp3');
    });

    test('parses Jamendo field names', () {
      final track = MusicTrack.fromJson({
        'id': 456,
        'name': 'Jamendo Song',
        'artist_name': 'Jamendo Artist',
        'album_image': 'https://example.com/album.jpg',
        'audio': 'https://example.com/stream.mp3',
      });

      expect(track.id, '456');
      expect(track.title, 'Jamendo Song');
      expect(track.artist, 'Jamendo Artist');
      expect(track.image, 'https://example.com/album.jpg');
      expect(track.streamUrl, 'https://example.com/stream.mp3');
    });

    test('uses safe defaults and null stream when fields are missing', () {
      final track = MusicTrack.fromJson({'id': 'missing-fields'});

      expect(track.id, 'missing-fields');
      expect(track.title, 'Unknown title');
      expect(track.artist, 'Unknown artist');
      expect(track.image, '');
      expect(track.streamUrl, isNull);
    });

    test('treats a blank stream URL as absent', () {
      final track = MusicTrack.fromJson({'id': '1', 'audio': '   '});

      expect(track.streamUrl, isNull);
    });
  });
}
