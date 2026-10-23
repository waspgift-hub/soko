import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:soko_vibe_music/models/music_track.dart';
import 'package:soko_vibe_music/services/music_api.dart';

void main() {
  group('MusicApi v2', () {
    test('uses the requested v2 Worker as the default base URL', () {
      expect(
        MusicApi().baseUrl,
        'https://soko-vibe-music-backend.wapalila.workers.dev',
      );
    });

    test('search sends pagination and parses v2 Jamendo fields', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/search');
        expect(request.url.queryParameters, {
          'q': 'bongo flava',
          'page': '2',
          'limit': '3',
        });
        return http.Response(jsonEncode({
          'results': [
            {
              'id': '123',
              'title': 'Afro track',
              'artist': 'Artist',
              'album': 'Album',
              'image': 'https://cdn.example.test/cover.jpg',
              'streaming_url': 'https://cdn.example.test/track.mp3',
              'audiodownload': 'https://cdn.example.test/download.mp3',
              'audiodownload_allowed': true,
              'license': 'https://creativecommons.org/licenses/by/4.0/',
              'duration': 123,
              'source': 'jamendo',
            }
          ],
          'count': 1,
          'source': 'jamendo',
        }), 200, headers: {'content-type': 'application/json'});
      });
      final api = MusicApi(baseUrl: 'https://music.example.test', client: client);
      final tracks = await api.search(' bongo flava ', page: 2, limit: 3);
      expect(tracks, hasLength(1));
      expect(tracks.single.title, 'Afro track');
      expect(tracks.single.canDownload, isTrue);
      expect(tracks.single.durationSeconds, 123);
      api.close();
    });

    test('falls back to Render open-license catalog when Worker search fails', () async {
      final client = MockClient((request) async {
        if (request.url.host == 'music.example.test') {
          return http.Response(jsonEncode({
            'error': 'PROVIDER_ERROR',
            'message': 'Music provider request failed.',
          }), 502);
        }
        expect(request.url.host, 'sokovibe-music-api.onrender.com');
        expect(request.url.path, '/api/v1/catalog/search');
        expect(request.url.queryParameters['kind'], 'music');
        return http.Response(jsonEncode({
          'success': true,
          'results': [
            {
              'id': 'archive-item-1',
              'provider': 'internet-archive',
              'kind': 'music',
              'title': 'Open license track',
              'creator': 'Archive artist',
              'image': 'https://archive.org/services/img/archive-item-1',
              'license': 'https://creativecommons.org/licenses/by/4.0/',
              'sourceUrl': 'https://archive.org/details/archive-item-1',
              'streamLookupUrl': '/api/v1/catalog/play/internet-archive/archive-item-1?kind=music',
              'downloadAllowed': true,
            }
          ],
        }), 200, headers: {'content-type': 'application/json'});
      });
      final api = MusicApi(baseUrl: 'https://music.example.test', client: client);
      final tracks = await api.search('ambient');
      expect(tracks, hasLength(1));
      expect(tracks.single.source, 'internet-archive');
      expect(tracks.single.artist, 'Archive artist');
      expect(tracks.single.streamLookupUrl, contains('/api/v1/catalog/play/'));
      expect(tracks.single.canDownload, isFalse);
      api.close();
    });

    test('resolves Render Internet Archive lookup to a validated HTTPS stream', () async {
      final client = MockClient((request) async {
        expect(request.url.host, 'sokovibe-music-api.onrender.com');
        expect(request.url.path, '/api/v1/catalog/play/internet-archive/archive-item-1');
        expect(request.url.queryParameters['kind'], 'music');
        return http.Response(jsonEncode({
          'success': true,
          'streamUrl': 'https://archive.org/download/archive-item-1/audio.mp3',
        }), 200, headers: {'content-type': 'application/json'});
      });
      final api = MusicApi(baseUrl: 'https://music.example.test', client: client);
      final track = MusicTrack.fromJson({
        'id': 'archive-item-1',
        'provider': 'internet-archive',
        'title': 'Archive track',
        'streamLookupUrl': '/api/v1/catalog/play/internet-archive/archive-item-1?kind=music',
      });
      expect(
        await api.playUrl(track.id, track: track),
        'https://archive.org/download/archive-item-1/audio.mp3',
      );
      api.close();
    });

    test('reuses an HTTPS stream URL from search without a second request', () async {
      var requestCount = 0;
      final client = MockClient((request) async {
        requestCount++;
        return http.Response('{}', 500);
      });
      final api = MusicApi(baseUrl: 'https://music.example.test', client: client);
      expect(
        await api.playUrl('123', streamUrl: 'https://cdn.example.test/track.mp3'),
        'https://cdn.example.test/track.mp3',
      );
      expect(requestCount, 0);
      api.close();
    });

    test('does not reuse an insecure HTTP stream URL', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/play/123');
        return http.Response(jsonEncode({
          'track': {
            'id': '123',
            'title': 'Playable',
            'artist': 'Artist',
            'streaming_url': 'https://cdn.example.test/secure-track.mp3',
          }
        }), 200);
      });
      final api = MusicApi(baseUrl: 'https://music.example.test', client: client);
      expect(
        await api.playUrl('123', streamUrl: 'http://cdn.example.test/track.mp3'),
        'https://cdn.example.test/secure-track.mp3',
      );
      api.close();
    });

    test('play resolves JSON metadata to the actual HTTPS stream URL', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/play/123');
        return http.Response(jsonEncode({
          'track': {
            'id': '123',
            'title': 'Playable',
            'artist': 'Artist',
            'streaming_url': 'https://cdn.example.test/track.mp3',
            'audiodownload': 'https://cdn.example.test/download.mp3',
            'audiodownload_allowed': true,
          }
        }), 200);
      });
      final api = MusicApi(baseUrl: 'https://music.example.test', client: client);
      expect(await api.playUrl('123'), 'https://cdn.example.test/track.mp3');
      api.close();
    });

    test('blocks download when provider says it is not allowed', () async {
      final client = MockClient((request) async => http.Response(
        jsonEncode({'track': {
          'id': '123',
          'title': 'Restricted',
          'artist': 'Artist',
          'streaming_url': 'https://cdn.example.test/track.mp3',
          'audiodownload': 'https://cdn.example.test/download.mp3',
          'audiodownload_allowed': false,
        }}), 200));
      final api = MusicApi(baseUrl: 'https://music.example.test', client: client);
      await expectLater(
        api.downloadUrl('123'),
        throwsA(isA<MusicApiException>().having(
          (e) => e.category, 'category', 'DOWNLOAD_NOT_ALLOWED',
        )),
      );
      api.close();
    });

    test('recommendations support the documented POST body', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/recommend');
        expect(jsonDecode(request.body), {
          'mood': 'happy',
          'genre': 'afrobeat',
          'language': 'Swahili',
          'limit': 5,
        });
        return http.Response(jsonEncode({'recommendations': [
          {'id': '77', 'title': 'Recommended', 'artist': 'Artist'}
        ]}), 200);
      });
      final api = MusicApi(baseUrl: 'https://music.example.test', client: client);
      final tracks = await api.recommend(mood: 'happy', language: 'Swahili', limit: 5);
      expect(tracks.single.title, 'Recommended');
      api.close();
    });

    test('AI lyrics sends the documented POST body and parses lyrics', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/lyrics');
        expect(jsonDecode(request.body), {
          'theme': 'hope',
          'genre': 'afrobeat',
          'language': 'English',
        });
        return http.Response(jsonEncode({'lyrics': 'Original test lyrics'}), 200);
      });
      final api = MusicApi(baseUrl: 'https://music.example.test', client: client);
      expect(
        await api.generateLyrics(theme: 'hope', genre: 'afrobeat', language: 'English'),
        'Original test lyrics',
      );
      api.close();
    });

    test('rejects invalid IDs before making requests', () async {
      final client = MockClient((_) async => http.Response('{}', 200));
      final api = MusicApi(baseUrl: 'https://music.example.test', client: client);
      await expectLater(api.playUrl('../bad'), throwsA(isA<MusicApiException>()));
      api.close();
    });
  });
}
