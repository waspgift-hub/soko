import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:soko_vibe_music/services/music_api.dart';

void main() {
  group('MusicApi', () {
    test('search parses real track response shape', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/search');
        expect(request.url.queryParameters['q'], 'afrobeat');
        return http.Response(jsonEncode({
          'results': [
            {
              'id': '123',
              'title': 'Afro track',
              'artist': 'Artist',
              'streaming_url': 'https://cdn.example.test/track.mp3',
              'audiodownload': 'https://cdn.example.test/download.mp3',
              'audiodownload_allowed': true,
              'source': 'jamendo',
            }
          ],
          'count': 1,
          'source': 'jamendo',
        }), 200, headers: {'content-type': 'application/json'});
      });
      final api = MusicApi(baseUrl: 'https://music.example.test', client: client);
      final tracks = await api.search(' afrobeat ');

      expect(tracks, hasLength(1));
      expect(tracks.single.title, 'Afro track');
      expect(tracks.single.canDownload, isTrue);
      api.close();
    });

    test('playUrl rejects a non-HTTPS URL', () async {
      final client = MockClient((_) async => http.Response(
            jsonEncode({'streaming_url': 'http://bad.example.test/song.mp3'}),
            200,
            headers: {'content-type': 'application/json'},
          ));
      final api = MusicApi(baseUrl: 'https://music.example.test', client: client);

      await expectLater(api.playUrl('123'), throwsA(isA<Exception>()));
      api.close();
    });
  });
}
