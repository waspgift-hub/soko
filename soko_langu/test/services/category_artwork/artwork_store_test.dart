import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/services/category_artwork/artwork_downloader.dart';
import 'package:soko_vibe/services/category_artwork/artwork_manifest.dart';
import 'package:soko_vibe/services/category_artwork/artwork_store.dart';

/// Serves a real pack over loopback HTTP so install/atomicity is exercised
/// against actual bytes rather than a mocked client.
class _FakePackServer {
  HttpServer? _server;
  late Uri baseUrl;

  /// asset id -> bytes
  final Map<String, List<int>> files = {};

  int manifestRequests = 0;

  Future<void> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    baseUrl = Uri.parse('http://127.0.0.1:${server.port}/artwork/');
    server.listen((req) async {
      final key = req.uri.path.replaceFirst('/artwork/', '');
      if (key == 'manifest.json') {
        manifestRequests++;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(_manifestJson()));
        await req.response.close();
        return;
      }
      final bytes = files[key];
      if (bytes == null) {
        req.response.statusCode = 404;
        await req.response.close();
        return;
      }
      // Honour Range so resume paths are real.
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

  Map<String, dynamic> _manifestJson() {
    final assets = <Map<String, dynamic>>[];
    for (final entry in files.entries) {
      final bytes = entry.value;
      final id = entry.key.split('|').first;
      final type = entry.key.split('|').last;
      assets.add({
        'id': id,
        'type': type,
        if (type == 'subcategory') 'categoryId': id.split('/').first,
        // Mirrors the real pack layout: categories at the top, subcategories
        // nested under their owning category.
        'file': type == 'subcategory'
            ? '1/subcategories/$id.webp'
            : '1/categories/$id.webp',
        'sha256': _sha256Hex(bytes),
        'size': bytes.length,
        'width': 10,
        'height': 10,
      });
    }
    return {
      'version': 1,
      'pack': 'category_artwork',
      'minAppVersion': '1.0.0',
      'generatedAt': '2026-01-01T00:00:00Z',
      'assets': assets,
    };
  }

  Future<void> stop() async => _server?.close(force: true);
}

String _sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

void main() {
  late _FakePackServer server;
  late Directory tmp;
  late ArtworkStore store;

  setUp(() async {
    server = _FakePackServer();
    await server.start();
    tmp = await Directory.systemTemp.createTemp('artwork_store_test');
    store = ArtworkStore()..debugUseRoot(tmp);
  });

  tearDown(() async {
    await server.stop();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<ArtworkManifest> manifestFor(List<String> ids) async {
    for (final id in ids) {
      server.files['$id|${id.contains('/') ? 'subcategory' : 'category'}'] =
          List<int>.generate(64, (i) => i);
    }
    return await ArtworkDownloader(baseUrl: server.baseUrl).fetchManifest();
  }

  group('with no pack installed', () {
    test('readInstalledVersion is null', () async {
      expect(await store.readInstalledVersion(), isNull);
      expect(await store.readInstalledManifest(), isNull);
      expect(await store.diskUsage(), 0);
    });

    test('localPathOf is null, not an exception', () async {
      expect(await store.localPathOf('categories/electronics.webp', 1), isNull);
    });
  });

  group('atomic install', () {
    test('installs a verified pack and exposes its files', () async {
      final manifest = await manifestFor(['electronics', 'fashion']);
      await store.ensureStagingDir(1);
      for (final asset in manifest.assets) {
        final staged = await store.stagedFile(1, asset.file.replaceFirst('1/', ''));
        await staged.parent.create(recursive: true);
        await staged.writeAsBytes(server.files['${asset.id}|${asset.type.name}']!);
      }

      final ok = await store.install(
        version: 1,
        manifest: manifest,
        manifestJson: '{}',
      );

      expect(ok, isTrue);
      expect(await store.readInstalledVersion(), 1);
      expect(await store.localPathOf('1/categories/electronics.webp', 1),
          isNotNull);
    });

    test('refuses to install when a file is missing from staging', () async {
      final manifest = await manifestFor(['electronics', 'fashion']);
      await store.ensureStagingDir(1);
      // Only stage one of the two declared assets.
      final staged = await store.stagedFile(1, '1/categories/electronics.webp');
      await staged.parent.create(recursive: true);
      await staged.writeAsBytes([1, 2, 3]);

      final ok = await store.install(
        version: 1,
        manifest: manifest,
        manifestJson: '{}',
      );

      expect(ok, isFalse);
      // Nothing became visible.
      expect(await store.readInstalledVersion(), isNull);
    });

    test('a failed install leaves the previous version active', () async {
      // v1 installs cleanly.
      server.files['electronics|category'] = List<int>.filled(32, 1);
      final v1 = await manifestFor(['electronics']);
      await store.ensureStagingDir(1);
      for (final asset in v1.assets) {
        final f = await store.stagedFile(1, asset.file.replaceFirst('1/', ''));
        await f.parent.create(recursive: true);
        await f.writeAsBytes([1]);
      }
      await store.install(version: 1, manifest: v1, manifestJson: '{}');
      expect(await store.readInstalledVersion(), 1);

      // v2 staging is incomplete -> install must fail and keep v1.
      server.files['fashion|category'] = List<int>.filled(32, 2);
      final v2Json = await _bumpVersion(server, 2, ['electronics', 'fashion']);
      final v2 = ArtworkManifest.parse(v2Json);
      await store.ensureStagingDir(2);
      final partial = await store.stagedFile(2, '2/categories/electronics.webp');
      await partial.parent.create(recursive: true);
      await partial.writeAsBytes([9, 9]);

      final ok = await store.install(
        version: 2,
        manifest: v2,
        manifestJson: '{}',
      );

      expect(ok, isFalse);
      expect(await store.readInstalledVersion(), 1);
      expect(
        await store.localPathOf('1/categories/electronics.webp', 1),
        isNotNull,
      );
    });
  });

  group('housekeeping', () {
    test('installing a new version prunes the old one', () async {
      server.files['electronics|category'] = List<int>.filled(32, 1);
      final v1 = await manifestFor(['electronics']);
      await store.ensureStagingDir(1);
      final f1 = await store.stagedFile(1, '1/categories/electronics.webp');
      await f1.parent.create(recursive: true);
      await f1.writeAsBytes([1]);
      await store.install(version: 1, manifest: v1, manifestJson: '{}');

      final v2Json = await _bumpVersion(server, 2, ['electronics']);
      final v2 = ArtworkManifest.parse(v2Json);
      await store.ensureStagingDir(2);
      final f2 = await store.stagedFile(2, '2/categories/electronics.webp');
      await f2.parent.create(recursive: true);
      await f2.writeAsBytes([2]);
      await store.install(version: 2, manifest: v2, manifestJson: '{}');

      expect(await store.readInstalledVersion(), 2);
      final versions = Directory('${tmp.path}${Platform.pathSeparator}versions');
      final names = versions
          .listSync()
          .map((e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last)
          .toList()
        ..sort();
      expect(names, ['2']);
    });

    test('uninstall clears everything and reads as not installed', () async {
      server.files['electronics|category'] = List<int>.filled(32, 1);
      final v1 = await manifestFor(['electronics']);
      await store.ensureStagingDir(1);
      final f1 = await store.stagedFile(1, '1/categories/electronics.webp');
      await f1.parent.create(recursive: true);
      await f1.writeAsBytes([1]);
      await store.install(version: 1, manifest: v1, manifestJson: '{}');

      await store.uninstall();

      expect(await store.readInstalledVersion(), isNull);
      expect(await store.diskUsage(), 0);
    });

    test('a pointer to a deleted directory reads as not installed', () async {
      // Simulates a manual clear or a failed migration leaving a stale pointer.
      server.files['electronics|category'] = List<int>.filled(32, 1);
      final v1 = await manifestFor(['electronics']);
      await store.ensureStagingDir(1);
      final f1 = await store.stagedFile(1, '1/categories/electronics.webp');
      await f1.parent.create(recursive: true);
      await f1.writeAsBytes([1]);
      await store.install(version: 1, manifest: v1, manifestJson: '{}');

      await Directory('${tmp.path}${Platform.pathSeparator}versions${Platform.pathSeparator}1').delete(recursive: true);

      expect(await store.readInstalledVersion(), isNull);
    });

    test('corrupt active.json does not throw', () async {
      await File('${tmp.path}${Platform.pathSeparator}active.json').writeAsString('{not json');
      expect(await store.readInstalledVersion(), isNull);
    });

    test('clearStaging removes a partial download', () async {
      await store.ensureStagingDir(3);
      final f = await store.stagedFile(3, '3/categories/x.webp');
      await f.parent.create(recursive: true);
      await f.writeAsBytes([1]);
      expect(await store.hasStagedFile(3, '3/categories/x.webp'), isTrue);

      await store.clearStaging(3);

      expect(await store.hasStagedFile(3, '3/categories/x.webp'), isFalse);
    });
  });
}

Future<String> _bumpVersion(
  _FakePackServer server,
  int version,
  List<String> ids,
) async {
  for (final id in ids) {
    server.files['$id|${id.contains('/') ? 'subcategory' : 'category'}'] =
        List<int>.filled(32, version);
  }
  return jsonEncode({
    'version': version,
    'pack': 'category_artwork',
    'minAppVersion': '1.0.0',
    'generatedAt': '2026-01-01T00:00:00Z',
    'assets': [
      for (final id in ids)
        {
          'id': id,
          'type': id.contains('/') ? 'subcategory' : 'category',
          if (id.contains('/')) 'categoryId': id.split('/').first,
          'file': '$version/categories/$id.webp',
          'sha256': _sha256Hex(server.files['$id|${id.contains('/') ? 'subcategory' : 'category'}']!),
          'size': 32,
          'width': 10,
          'height': 10,
        },
    ],
  });
}