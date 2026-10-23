import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

  test('music API defaults to the deployed music-api Worker', () {
    final api = MusicApi();
    expect(
      api.baseUrl,
      'https://soko-vibe-music-backend.wapalila.workers.dev',
    );
    api.close();
  });

  test('music API parses the deployed song and cover response fields', () {
    final track = MusicTrack.fromJson({
      'id': '42',
      'song': 'Test Song',
      'artist': 'Test Artist',
      'cover': 'https://example.test/cover.jpg',
      'audio': 'https://soko-vibe-music-backend.wapalila.workers.dev/play/42',
      'download': 'https://soko-vibe-music-backend.wapalila.workers.dev/download/42',
      'audiodownload_allowed': true,
    });

    expect(track.title, 'Test Song');
    expect(track.artist, 'Test Artist');
    expect(track.image, 'https://example.test/cover.jpg');
    expect(track.streamUrl, contains('/play/42'));
    expect(track.downloadUrl, contains('/download/42'));
    expect(track.downloadAllowed, isTrue);
  });

  test('music API returns empty results for a blank query without networking', () async {
    final api = MusicApi(baseUrl: 'https://example.invalid');
    expect(await api.search('  '), isEmpty);
    api.close();
  });

  test('search calls the Worker and parses its result envelope', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/search');
      expect(request.url.queryParameters['q'], 'afrobeat');
      return http.Response(
        jsonEncode({
          'query': 'afrobeat',
          'count': 1,
          'results': [
            {
              'id': '42',
              'song': 'Test Song',
              'artist': 'Test Artist',
              'cover': 'https://example.test/cover.jpg',
              'audio': 'https://worker.example.test/play/42',
              'download': null,
              'audiodownload_allowed': false,
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = MusicApi(baseUrl: 'https://worker.example.test', client: client);

    final results = await api.search('  afrobeat  ');

    expect(results, hasLength(1));
    expect(results.single.id, '42');
    expect(results.single.title, 'Test Song');
    expect(results.single.artist, 'Test Artist');
    expect(results.single.downloadAllowed, isFalse);
    api.close();
  });

  test('search reports an HTTP error instead of parsing an error page', () async {
    final client = MockClient((_) async => http.Response('upstream failed', 502));
    final api = MusicApi(baseUrl: 'https://worker.example.test', client: client);

    await expectLater(api.search('afrobeat'), throwsA(isA<Exception>()));
    api.close();
  });

  test('playback resolves Worker JSON metadata to the HTTPS stream', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/play/42');
      return http.Response(
        jsonEncode({
          'track': {
            'id': '42',
            'streaming_url': 'https://audio.example.test/track.mp3',
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = MusicApi(baseUrl: 'https://worker.example.test', client: client);

    expect(await api.playUrl('42'), 'https://audio.example.test/track.mp3');
    api.close();
  });

  test('download uses the Worker permission-checking endpoint', () async {
    final api = MusicApi(baseUrl: 'https://worker.example.test');
    expect(await api.downloadUrl('42'), 'https://worker.example.test/download/42');
    api.close();
  });

  test('track parser marks disallowed downloads as unavailable', () {
    final track = MusicTrack.fromJson({
      'id': '42',
      'song': 'Streaming Only',
      'audiodownload_allowed': false,
      'download': null,
    });

    expect(track.downloadAllowed, isFalse);
    expect(track.downloadUrl, isNull);
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
      'audiodownload': 'https://example.com/download.mp3',
      'audiodownload_allowed': true,
    });

    expect(track.id, '123');
    expect(track.title, 'Test Song');
    expect(track.artist, 'Test Artist');
    expect(track.image, 'https://example.com/cover.jpg');
    expect(track.streamUrl, 'https://example.com/audio.mp3');
    expect(track.downloadUrl, 'https://example.com/download.mp3');
    expect(track.downloadAllowed, isTrue);
  });
}
