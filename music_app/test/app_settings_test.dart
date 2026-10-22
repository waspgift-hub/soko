import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soko_vibe_music/models/music_track.dart';
import 'package:soko_vibe_music/services/app_settings.dart';
import 'package:soko_vibe_music/services/music_api.dart';
import 'package:soko_vibe_music/services/download_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('startup sound is enabled by default', () async {
    final settings = AppSettings();
    await settings.load();

    expect(settings.startupSound, isTrue);
  });

  test('startup sound preference persists when changed', () async {
    final settings = AppSettings();
    await settings.load();

    await settings.saveStartupSound(false);
    final reloaded = AppSettings();
    await reloaded.load();

    expect(reloaded.startupSound, isFalse);
  });

  test('music API returns empty results for a blank query without networking', () async {
    final api = MusicApi(baseUrl: 'https://example.invalid');
    expect(await api.search('  '), isEmpty);
  });

  test('download metadata survives JSON serialization', () {
    final original = DownloadedTrack(
      id: 'track-42',
      title: 'Offline Song',
      artist: 'Soko Artist',
      image: 'https://example.com/cover.jpg',
      filePath: '/private/music/track-42.mp3',
      downloadedAt: DateTime.utc(2026, 10, 22),
    );
    final restored = DownloadedTrack.fromJson(original.toJson());

    expect(restored.id, original.id);
    expect(restored.title, original.title);
    expect(restored.artist, original.artist);
    expect(restored.filePath, original.filePath);
    expect(restored.downloadedAt, original.downloadedAt);
  });

  test('music track maps Jamendo response fields correctly', () {
    final track = MusicTrack.fromJson({
      'id': 123,
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
}
