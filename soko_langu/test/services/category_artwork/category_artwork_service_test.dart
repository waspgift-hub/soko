import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/data/marketplace_taxonomy.dart';
import 'package:soko_vibe/services/category_artwork/artwork_downloader.dart';
import 'package:soko_vibe/services/category_artwork/category_artwork_service.dart';

/// Serves a pack over loopback HTTP so the full install path (download →
/// verify → atomic promote → resolve) runs against real bytes.
class _FakePack {
  HttpServer? _server;
  late Uri baseUrl;
  final Map<String, List<int>> files = {};
  int manifestRequests = 0;
  int assetRequests = 0;

  Future<void> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    baseUrl = Uri.parse('http://127.0.0.1:${server.port}/artwork/');
    server.listen((req) async {
      final key = req.uri.path.replaceFirst('/artwork/', '');
      if (key == 'manifest.json') {
        manifestRequests++;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(_manifest()));
        await req.response.close();
        return;
      }
      assetRequests++;
      final bytes = files[key];
      if (bytes == null) {
        req.response.statusCode = 404;
        await req.response.close();
        return;
      }
      final range = req.headers.value('range');
      if (range != null) {
        final start = int.parse(
          range.replaceAll('bytes=', '').split('-').first,
        );
        req.response.statusCode = 206;
        req.response.add(bytes.sublist(start));
      } else {
        req.response.add(bytes);
      }
      await req.response.close();
    });
  }

  Map<String, dynamic> _manifest() {
    return {
      'version': 1,
      'pack': 'category_artwork',
      'minAppVersion': '1.0.0',
      'generatedAt': '2026-01-01T00:00:00Z',
      'assets': [
        for (final e in files.entries)
          {
            'id': e.key.split('|').first,
            'type': e.key.split('|').last,
            if (e.key.contains('/'))
              'categoryId': e.key.split('|').first.split('/').first,
            'file': '1/${e.key.split('|').first}.webp',
            'sha256': sha256.convert(e.value).toString(),
            'size': e.value.length,
            'width': 720,
            'height': 540,
          },
      ],
    };
  }

  Future<void> stop() async => _server?.close(force: true);
}

void main() {
  late _FakePack pack;

  setUp(() async {
    pack = _FakePack();
    await pack.start();
  });

  tearDown(() async => pack.stop());

  group('subcategory id ambiguity', () {
    test('cleaning exists under both kitchen and services', () {
      // This is why artwork keys are `categoryId/subId` and not the bare slug.
      final ambiguous =
          CategoryArtworkService.findAmbiguousSubcategoryIds();
      expect(ambiguous.containsKey('cleaning'), isTrue);
      expect(ambiguous['cleaning'], containsAll(['kitchen', 'services']));
    });

    test('subKey qualifies a slug with its owning category', () {
      expect(
        CategoryArtworkService.subKey('kitchen', 'cleaning'),
        'kitchen/cleaning',
      );
    });
  });

  group('taxonomy expectations', () {
    test('taxonomy declares 20 categories and 131 subcategories', () {
      // 131, not 130: `cleaning` is declared twice (kitchen + services), so
      // there are 131 subcategory declarations but only 130 distinct slugs.
      // That collision is exactly why artwork keys are qualified.
      final counts = CategoryArtworkService.expectedArtworkCounts;
      expect(counts.categories, 20);
      expect(counts.subcategories, 131);
      expect(counts.categories, kMarketplaceTaxonomy.length);

      final distinct = <String>{};
      for (final c in kMarketplaceTaxonomy) {
        for (final s in c.subs) {
          distinct.add(s.id);
        }
      }
      expect(distinct, hasLength(130));
    });

    test('subcategory ids are unique once qualified by category', () {
      final qualified = <String>{};
      for (final c in kMarketplaceTaxonomy) {
        for (final s in c.subs) {
          expect(
            qualified.add(CategoryArtworkService.subKey(c.id, s.id)),
            isTrue,
            reason: 'duplicate qualified id ${c.id}/${s.id}',
          );
        }
      }
    });
  });

  group('live-pack contract', () {
    test('a pack that omits categories reports them as missing', () async {
      // Deliberately partial: the contract is that gaps are *visible*, not
      // silently rendered as icons. The full published pack is checked by the
      // network-tagged integration test.
      pack.files['electronics|category'] = List<int>.filled(128, 1);
      final downloader = ArtworkDownloader(baseUrl: pack.baseUrl);
      addTearDown(downloader.dispose);
      final manifest = await downloader.fetchManifest();

      expect(manifest.assetForCategory('electronics'), isNotNull);
      expect(manifest.assetForCategory('fashion'), isNull);

      final missing = kMarketplaceTaxonomy
          .map((t) => t.id)
          .where((id) => manifest.assetForCategory(id) == null)
          .toList();
      expect(missing, hasLength(19));
      expect(missing, isNot(contains('electronics')));
    });

    test('with zero artwork installed every category id resolves to null',
        () async {
      // The critical non-dependency guarantee: no pack means no artwork, and
      // every lookup returns null rather than throwing or pointing at a
      // missing file, so the UI falls back to icons.
      final service = CategoryArtworkService.instance;
      service.offlineMode = true;
      await service.initialize();

      expect(service.status, ArtworkStatus.notInstalled);
      expect(service.hasArtwork, isFalse);
      expect(service.resolveCategory('electronics'), isNull);
      expect(
        service.resolveSubcategory('kitchen', 'cleaning'),
        isNull,
      );
      // Every taxonomy id must resolve to null, not blow up.
      for (final c in kMarketplaceTaxonomy) {
        expect(service.resolveCategory(c.id), isNull);
        for (final s in c.subs) {
          expect(service.resolveSubcategory(c.id, s.id), isNull);
        }
      }
      expect(service.missingCategoryIds(), hasLength(20));
    });
  });
}