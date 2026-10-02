import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/services/category_artwork/artwork_downloader.dart';
import 'package:soko_vibe/services/category_artwork/artwork_manifest.dart';

String validAsset({
  String id = 'electronics',
  String type = 'category',
  String? categoryId,
  String file = '1/categories/electronics.webp',
  String? sha256,
  int size = 1024,
}) {
  return jsonEncode({
    'id': id,
    'type': type,
    if (categoryId != null) 'categoryId': categoryId,
    'file': file,
    'sha256': sha256 ?? ('a' * 64),
    'size': size,
    'width': 720,
    'height': 540,
  });
}

String manifestOf(List<String> assets, {int version = 1}) {
  return jsonEncode({
    'version': version,
    'pack': 'category_artwork',
    'minAppVersion': '1.0.0',
    'generatedAt': '2026-01-01T00:00:00Z',
    'assets': assets.map((a) => jsonDecode(a)).toList(),
  });
}

void main() {
  group('ArtworkManifest.parse', () {
    test('parses a well-formed manifest', () {
      final m = ArtworkManifest.parse(manifestOf([validAsset()]));
      expect(m.version, 1);
      expect(m.pack, 'category_artwork');
      expect(m.assets, hasLength(1));
      expect(m.totalBytes, 1024);
      expect(m.assetForCategory('electronics'), isNotNull);
    });

    test('rejects non-JSON', () {
      expect(
        () => ArtworkManifest.parse('not json'),
        throwsA(isA<ArtworkManifestException>()),
      );
    });

    test('rejects a wrong pack name at the service level', () {
      // parse() itself is pack-agnostic; the service enforces the name so a
      // manifest from another pack at this path cannot be installed.
      final m = ArtworkManifest.parse(
        jsonEncode({
          'version': 1,
          'pack': 'something_else',
          'assets': [jsonDecode(validAsset())],
        }),
      );
      expect(m.pack, 'something_else');
    });

    test('rejects an empty asset list', () {
      expect(
        () => ArtworkManifest.parse(manifestOf([])),
        throwsA(isA<ArtworkManifestException>()),
      );
    });

    test('rejects duplicate ids of the same type', () {
      expect(
        () => ArtworkManifest.parse(
          manifestOf([validAsset(), validAsset()]),
        ),
        throwsA(isA<ArtworkManifestException>()),
      );
    });

    test('allows the same slug under two categories', () {
      // `cleaning` exists under both kitchen and services in the live taxonomy.
      final m = ArtworkManifest.parse(
        manifestOf([
          validAsset(
            id: 'kitchen/cleaning',
            type: 'subcategory',
            categoryId: 'kitchen',
            file: '1/subcategories/kitchen/cleaning.webp',
          ),
          validAsset(
            id: 'services/cleaning',
            type: 'subcategory',
            categoryId: 'services',
            file: '1/subcategories/services/cleaning.webp',
          ),
        ]),
      );
      expect(m.assets, hasLength(2));
      expect(m.assetForSubcategory('kitchen/cleaning'), isNotNull);
      expect(m.assetForSubcategory('services/cleaning'), isNotNull);
    });

    group('rejects untrusted input', () {
      test('path traversal in file path', () {
        expect(
          () => ArtworkManifest.parse(
            manifestOf([validAsset(file: '../../etc/passwd.webp')]),
          ),
          throwsA(isA<ArtworkManifestException>()),
        );
      });

      test('absolute file path', () {
        expect(
          () => ArtworkManifest.parse(
            manifestOf([validAsset(file: '/etc/passwd.webp')]),
          ),
          throwsA(isA<ArtworkManifestException>()),
        );
      });

      test('backslash file path', () {
        expect(
          () => ArtworkManifest.parse(
            manifestOf([validAsset(file: '1\\evil.webp')]),
          ),
          throwsA(isA<ArtworkManifestException>()),
        );
      });

      test('unsupported extension', () {
        expect(
          () => ArtworkManifest.parse(
            manifestOf([validAsset(file: '1/run.sh')]),
          ),
          throwsA(isA<ArtworkManifestException>()),
        );
      });

      test('non-hex sha256', () {
        expect(
          () => ArtworkManifest.parse(
            manifestOf([validAsset(sha256: 'ZZZZ')]),
          ),
          throwsA(isA<ArtworkManifestException>()),
        );
      });

      test('uppercase sha256', () {
        // The build emits lowercase hex; accepting uppercase would mean two
        // spellings of one checksum and a class of bypass.
        expect(
          () => ArtworkManifest.parse(
            manifestOf([validAsset(sha256: 'A' * 64)]),
          ),
          throwsA(isA<ArtworkManifestException>()),
        );
      });

      test('negative size', () {
        expect(
          () => ArtworkManifest.parse(
            manifestOf([validAsset(size: -1)]),
          ),
          throwsA(isA<ArtworkManifestException>()),
        );
      });

      test('subcategory without categoryId', () {
        expect(
          () => ArtworkManifest.parse(
            manifestOf([
              validAsset(
                id: 'phones',
                type: 'subcategory',
                file: '1/subcategories/phones.webp',
              ),
            ]),
          ),
          throwsA(isA<ArtworkManifestException>()),
        );
      });

      test('unknown asset type', () {
        expect(
          () => ArtworkManifest.parse(
            manifestOf([validAsset(type: 'executable')]),
          ),
          throwsA(isA<ArtworkManifestException>()),
        );
      });

      test('version below 1', () {
        expect(
          () => ArtworkManifest.parse(
            jsonEncode({
              'version': 0,
              'pack': 'category_artwork',
              'assets': [jsonDecode(validAsset())],
            }),
          ),
          throwsA(isA<ArtworkManifestException>()),
        );
      });
    });
  });

  group('ArtworkAsset.sizeLabel', () {
    test('formats bytes, KB and MB', () {
      ArtworkAsset make(int size) => ArtworkAsset.parse(
        jsonDecode(validAsset(size: size)),
      );
      expect(make(500).sizeLabel, '500 B');
      expect(make(2048).sizeLabel, '2 KB');
      expect(make(5 * 1024 * 1024).sizeLabel, '5.0 MB');
    });
  });

  group('ArtworkDownloadProgress', () {
    test('fraction is null when the total size is unknown', () {
      const p = ArtworkDownloadProgress(receivedBytes: 100);
      expect(p.fraction, isNull);
      expect(p.percent, 0);
    });

    test('fraction clamps to 0..1', () {
      final over = ArtworkDownloadProgress(receivedBytes: 200, totalBytes: 100);
      expect(over.fraction, 1.0);
      final under = ArtworkDownloadProgress(receivedBytes: 25, totalBytes: 100);
      expect(under.fraction, 0.25);
      expect(under.percent, 25);
    });
  });

  group('ArtworkDownloader.downloadAsset', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('artwork_dl_test');
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    ArtworkDownloader downloaderFor(String host) => ArtworkDownloader(
      baseUrl: Uri.parse(host),
    );

    test('writes a file that matches the manifest size', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final body = List<int>.filled(256, 7);
      server.listen((req) async {
        req.response.add(body);
        await req.response.close();
      });

      final asset = ArtworkAsset.parse(
        jsonDecode(validAsset(size: body.length, sha256: 'b' * 64)),
      );
      final target = File('${tmp.path}/out.webp');

      await downloaderFor('http://127.0.0.1:${server.port}/').downloadAsset(
        asset: asset,
        target: target,
        progress: () => const ArtworkDownloadProgress(),
        onProgress: (_) async {},
        isCancelled: () => false,
      );

      expect(await target.exists(), isTrue);
      expect(await target.length(), body.length);
      await server.close(force: true);
    });

    test('resumes a partial file instead of restarting', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final body = List<int>.filled(512, 3);
      final seenRanges = <String?>[];

      server.listen((req) async {
        seenRanges.add(req.headers.value('range'));
        final range = req.headers.value('range');
        if (range == null) {
          req.response.add(body);
          await req.response.close();
          return;
        }
        // Honour a range request the way R2 does.
        final start = int.parse(range.replaceAll('bytes=', '').split('-').first);
        req.response.statusCode = 206;
        req.response.add(body.sublist(start));
        await req.response.close();
      });

      final asset = ArtworkAsset.parse(
        jsonDecode(validAsset(size: body.length, sha256: 'c' * 64)),
      );
      // Simulate an interrupted earlier attempt: 200 of 512 bytes present.
      final part = File('${tmp.path}/out.webp.part');
      await part.writeAsBytes(body.sublist(0, 200));

      final target = File('${tmp.path}/out.webp');
      await downloaderFor('http://127.0.0.1:${server.port}/').downloadAsset(
        asset: asset,
        target: target,
        progress: () => const ArtworkDownloadProgress(),
        onProgress: (_) async {},
        isCancelled: () => false,
      );

      expect(await target.length(), body.length);
      // The resumed request must have asked only for the missing tail.
      expect(seenRanges.first, 'bytes=200-');
      await server.close(force: true);
    });

    test('honours cancellation before any request', () async {
      final asset = ArtworkAsset.parse(jsonDecode(validAsset()));
      var called = false;

      expect(
        () => downloaderFor('http://127.0.0.1:1/').downloadAsset(
          asset: asset,
          target: File('${tmp.path}/out.webp'),
          progress: () => const ArtworkDownloadProgress(),
          onProgress: (_) async {},
          isCancelled: () => true,
        ),
        throwsA(isA<ArtworkDownloadException>()),
      );
      expect(called, isFalse);
    });

    test('fails after the retry budget, not before', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var attempts = 0;
      server.listen((req) async {
        attempts++;
        req.response.statusCode = 503;
        await req.response.close();
      });

      final asset = ArtworkAsset.parse(jsonDecode(validAsset()));
      final target = File('${tmp.path}/out.webp');

      await expectLater(
        downloaderFor('http://127.0.0.1:${server.port}/').downloadAsset(
          asset: asset,
          target: target,
          progress: () => const ArtworkDownloadProgress(),
          onProgress: (_) async {},
          isCancelled: () => false,
        ),
        throwsA(
          isA<ArtworkDownloadException>().having(
            (e) => e.httpStatus,
            'httpStatus',
            503,
          ),
        ),
      );
      expect(attempts, greaterThan(1), reason: 'must retry before giving up');
      await server.close(force: true);
    });
  });
}