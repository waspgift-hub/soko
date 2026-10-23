import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:soko_vibe_music/services/music_api.dart';

void main() {
  test('defaults to the deployed SokoVibe Music Worker', () {
    final api = MusicApi();
    expect(api.baseUrl, 'https://soko-vibe-music-backend.wapalila.workers.dev');
    api.close();
  });

  test('search parses Jamendo tracks and license metadata', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'music.example.test');
      expect(request.url.path, '/search');
      expect(request.url.queryParameters['q'], 'afrobeat');
      return http.Response(
        jsonEncode({
          'results': [
            {
              'id': '123',
              'title': 'Example Track',
              'artist': 'Example Artist',
              'image': 'https://img.example.test/cover.jpg',
              'streaming_url': 'https://audio.example.test/track.mp3',
              'audiodownload': 'https://audio.example.test/download.mp3',
              'audiodownload_allowed': true,
              'source': 'jamendo',
            }
          ]
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = MusicApi(baseUrl: 'https://music.example.test', client: client);

    final tracks = await api.search(' afrobeat ');

    expect(tracks, hasLength(1));
    expect(tracks.single.id, '123');
    expect(tracks.single.title, 'Example Track');
    expect(tracks.single.streamUrl, 'https://audio.example.test/track.mp3');
    expect(tracks.single.downloadAllowed, isTrue);
    api.close();
  });

  test('playUrl resolves JSON metadata to the HTTPS audio stream', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/play/123');
      return http.Response(
        jsonEncode({
          'track': {
            'id': '123',
            'streaming_url': 'https://audio.example.test/track.mp3',
          }
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = MusicApi(baseUrl: 'https://music.example.test', client: client);

    expect(await api.playUrl('123'), 'https://audio.example.test/track.mp3');
    api.close();
  });

  test('playUrl rejects a non-HTTPS stream URL', () async {
    final client = MockClient((_) async => http.Response(
          jsonEncode({
            'track': {'id': '123', 'streaming_url': 'http://audio.example.test/track.mp3'}
          }),
          200,
        ));
    final api = MusicApi(baseUrl: 'https://music.example.test', client: client);

    await expectLater(api.playUrl('123'), throwsA(isA<FormatException>()));
    api.close();
  });

  test('downloadUrl targets the Worker license-check endpoint', () async {
    final api = MusicApi(baseUrl: 'https://music.example.test');

    expect(await api.downloadUrl('123'), 'https://music.example.test/download/123');
    api.close();
  });
}
