import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:soko_vibe_music/services/youtube_search_service.dart';

void main() {
  test('YouTube search parses title, channel, thumbnail and marks audio download unavailable', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'inv.example.test');
      expect(request.url.path, '/api/v1/search');
      expect(request.url.queryParameters['q'], 'Diamond Platnumz');
      expect(request.url.queryParameters['type'], 'video');
      return http.Response(
        jsonEncode([
          {
            'type': 'video',
            'videoId': 'abc123',
            'title': 'Example Song',
            'author': 'Example Channel',
            'videoThumbnails': [
              {'quality': 'medium', 'url': 'https://img.example.test/thumb.jpg'}
            ]
          }
        ]),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final service = YoutubeSearchService(
      client: client,
      instances: const ['https://inv.example.test'],
    );

    final results = await service.search('  Diamond Platnumz  ');

    expect(results, hasLength(1));
    expect(results.single.id, 'abc123');
    expect(results.single.title, 'Example Song');
    expect(results.single.artist, 'Example Channel');
    expect(results.single.image, 'https://img.example.test/thumb.jpg');
    expect(results.single.source, 'youtube');
    expect(results.single.streamUrl, isNull);
    expect(results.single.downloadAllowed, isFalse);
    service.close();
  });

  test('blank YouTube search returns empty results without a request', () async {
    final client = MockClient((_) async => throw StateError('Unexpected network request'));
    final service = YoutubeSearchService(
      client: client,
      instances: const ['https://inv.example.test'],
    );

    expect(await service.search('  '), isEmpty);
    service.close();
  });

  test('YouTube search fails clearly when all instances are unavailable', () async {
    final client = MockClient((_) async => http.Response('unavailable', 503));
    final service = YoutubeSearchService(
      client: client,
      instances: const ['https://inv.example.test'],
    );

    await expectLater(
      service.search('afrobeat'),
      throwsA(isA<Exception>()),
    );
    service.close();
  });
}
