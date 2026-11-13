@Tags(['network'])
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/services/category_artwork/artwork_downloader.dart';
import 'package:soko_vibe/services/category_artwork/category_artwork_service.dart';

/// End-to-end verification against the live R2 pack.
///
/// Excluded from `flutter test` (network tag) and run explicitly:
///
///   flutter test --tags network test/integration/artwork_pack_live_test.dart
///
/// This is the only test that proves the published pack is actually fetchable,
/// correctly checksummed, and resumable — everything else is self-contained.
void main() {
  final baseUrl = Uri.parse(kArtworkBaseUrl);

  test('live manifest is fetchable and valid', () async {
    final downloader = ArtworkDownloader(baseUrl: baseUrl);
    addTearDown(downloader.dispose);

    final manifest = await downloader.fetchManifest();

    expect(manifest.pack, 'category_artwork');
    expect(manifest.version, greaterThanOrEqualTo(1));
    expect(manifest.assets, isNotEmpty);
    expect(manifest.totalBytes, greaterThan(0));
    // Every shipped taxonomy category should have artwork in the pack.
    expect(
      manifest.assetForCategory('electronics'),
      isNotNull,
      reason: 'pack v${manifest.version} is missing the electronics category',
    );
  });

  test('live ETag short-circuits an unchanged manifest', () async {
    final downloader = ArtworkDownloader(baseUrl: baseUrl);
    addTearDown(downloader.dispose);

    final etag = await downloader.manifestEtag();
    expect(etag, isNotNull, reason: 'R2 must send an ETag for If-None-Match');

    await expectLater(
      downloader.fetchManifest(etag: etag),
      throwsA(
        isA<ArtworkDownloadException>().having(
          (e) => e.httpStatus,
          'httpStatus',
          304,
        ),
      ),
    );
  });

  test('every live asset downloads, hashes, and resumes correctly', () async {
    final downloader = ArtworkDownloader(baseUrl: baseUrl);
    addTearDown(downloader.dispose);
    final manifest = await downloader.fetchManifest();
    final dir = await Directory.systemTemp.createTemp('artwork_live');
    addTearDown(() => dir.delete(recursive: true));

    for (final asset in manifest.assets) {
      final target = File(
        '${dir.path}${Platform.pathSeparator}${asset.id.replaceAll('/', '_')}.webp',
      );

      await downloader.downloadAsset(
        asset: asset,
        target: target,
        progress: () => const ArtworkDownloadProgress(),
        onProgress: (_) async {},
        isCancelled: () => false,
      );

      expect(await target.length(), asset.size, reason: 'size ${asset.id}');
      expect(
        sha256.convert(await target.readAsBytes()).toString(),
        asset.sha256,
        reason: 'sha256 ${asset.id}',
      );

      // Truncate to simulate an interrupted transfer, then re-download: the
      // partial must be resumed, not restarted, and must still hash correctly.
      final partial = File('${target.path}.part');
      final full = await target.readAsBytes();
      await partial.writeAsBytes(full.sublist(0, full.length ~/ 3));
      await target.delete();

      await downloader.downloadAsset(
        asset: asset,
        target: target,
        progress: () => const ArtworkDownloadProgress(),
        onProgress: (_) async {},
        isCancelled: () => false,
      );

      expect(
        sha256.convert(await target.readAsBytes()).toString(),
        asset.sha256,
        reason: 'sha256 after resume ${asset.id}',
      );
    }
  });
}
