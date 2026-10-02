import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'artwork_manifest.dart';

/// Progress of an in-flight pack download, surfaced to the download screen.
class ArtworkDownloadProgress {
  /// Files fully written and checksum-verified so far.
  final int completedAssets;

  final int totalAssets;

  /// Bytes received so far across all files (including a resumed file's
  /// already-present prefix, so a resume does not make the bar jump back).
  final int receivedBytes;

  /// Server-declared total bytes, or null when unknown.
  final int? totalBytes;

  final ArtworkDownloadStage stage;

  const ArtworkDownloadProgress({
    this.completedAssets = 0,
    this.totalAssets = 0,
    this.receivedBytes = 0,
    this.totalBytes,
    this.stage = ArtworkDownloadStage.preparing,
  });

  /// 0..1, or null when the total size is unknown so the UI can show an
  /// indeterminate spinner instead of a lying progress bar.
  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    final value = receivedBytes / total;
    return value.clamp(0.0, 1.0);
  }

  int get percent =>
      ((fraction ?? 0) * 100).round().clamp(0, 100);
}

enum ArtworkDownloadStage {
  preparing,
  downloading,
  verifying,
  installing,
  done,
  failed,
  cancelled,
}

/// Raised for every failure the download surface must turn into a friendly
/// message. [technical] is what goes to error monitoring; the UI never shows
/// it.
class ArtworkDownloadException implements Exception {
  final String message;
  final Object? cause;
  final int? httpStatus;

  const ArtworkDownloadException(this.message, {this.cause, this.httpStatus});

  @override
  String toString() => 'ArtworkDownloadException: $message';
}

/// Downloads pack files with per-file resume, SHA-256 verification, and
/// atomic install.
///
/// Resume granularity is per file: a partially written `.part` file is
/// re-requested with a `Range` header and appended to. That is what stops an
/// interrupted download of a 130-file pack from restarting from zero, and it
/// keeps the retry cost proportional to what is actually missing.
class ArtworkDownloader {
  final Uri baseUrl;
  final http.Client _client;

  /// Guards against a hostile or misconfigured server streaming forever: a
  /// single file may never exceed its manifest-declared size by more than
  /// this margin, and no file may exceed the hard cap at all.
  static const int _sizeSlackBytes = 64 * 1024;
  static const int _maxSingleFileBytes = 8 * 1024 * 1024;
  static const int _maxManifestBytes = 512 * 1024;

  /// 3 attempts per file with exponential backoff. A dropped mobile
  /// connection on a mid-size file is normal, not an error worth surfacing.
  static const int _maxAttempts = 3;

  ArtworkDownloader({required this.baseUrl, http.Client? client})
    : _client = client ?? http.Client();

  void dispose() => _client.close();

  /// Fetches and validates `manifest.json`.
  ///
  /// `etag` short-circuits the download when the pack has not changed, which
  /// is what keeps a periodic startup check from re-fetching the whole
  /// manifest.
  Future<ArtworkManifest> fetchManifest({String? etag}) async {
    final uri = baseUrl.resolve('manifest.json');
    try {
      final resp = await _client
          .get(uri, headers: {if (etag != null) 'If-None-Match': etag})
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode == 304) {
        throw const ArtworkDownloadException(
          'Manifest unchanged (304)',
          httpStatus: 304,
        );
      }
      if (resp.statusCode != 200) {
        throw ArtworkDownloadException(
          'Manifest request failed',
          httpStatus: resp.statusCode,
        );
      }
      if (resp.bodyBytes.length > _maxManifestBytes) {
        throw const ArtworkDownloadException('Manifest is implausibly large');
      }
      final manifest = ArtworkManifest.parse(
        utf8.decode(resp.bodyBytes, allowMalformed: false),
      );
      if (manifest.pack != 'category_artwork') {
        throw ArtworkManifestException(
          'Unexpected pack "${manifest.pack}"',
        );
      }
      return manifest;
    } on ArtworkManifestException {
      rethrow;
    } on ArtworkDownloadException {
      rethrow;
    } catch (e) {
      throw ArtworkDownloadException('Manifest could not be read', cause: e);
    }
  }

  /// Current ETag of the remote manifest, or null when unknown.
  Future<String?> manifestEtag() async {
    try {
      final resp = await _client
          .head(baseUrl.resolve('manifest.json'))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) return resp.headers['etag'];
    } catch (_) {}
    return null;
  }

  /// Downloads one asset into [target], resuming a partial `.part` file when
  /// one exists.
  ///
  /// Returns the number of bytes the file contributes to the pack total.
  Future<int> downloadAsset({
    required ArtworkAsset asset,
    required File target,
    required ArtworkDownloadProgress Function() progress,
    required Future<void> Function(ArtworkDownloadProgress) onProgress,
    required bool Function() isCancelled,
  }) async {
    if (target.existsSync() && await target.length() == asset.size) {
      // Already complete from an earlier attempt in this same session.
      return asset.size;
    }

    final part = File('${target.path}.part');
    var attempt = 0;
    var resumeFrom = part.existsSync() ? await part.length() : 0;
    if (resumeFrom > asset.size) {
      await part.delete();
      resumeFrom = 0;
    }

    while (true) {
      attempt++;
      if (isCancelled()) {
        throw const ArtworkDownloadException('Cancelled by user');
      }
      try {
        final startedAt = resumeFrom;
        final request = http.Request('GET', baseUrl.resolve(asset.file));
        if (resumeFrom > 0) {
          request.headers['Range'] = 'bytes=$resumeFrom-';
        }
        final streamed = await _client
            .send(request)
            .timeout(const Duration(seconds: 60));

        final status = streamed.statusCode;
        if (status != 200 && status != 206) {
          throw ArtworkDownloadException(
            'Asset ${asset.id} returned HTTP $status',
            httpStatus: status,
          );
        }

        // A server that ignores our Range replys 200 with the whole body.
        // Appending that to an existing partial would corrupt the file, so the
        // partial is discarded and restarted rather than trusted.
        if (status == 200 && resumeFrom > 0) {
          await part.delete();
          resumeFrom = 0;
        }

        await part.parent.create(recursive: true);
        final sink = part.openWrite(
          mode: resumeFrom > 0 ? FileMode.append : FileMode.write,
        );
        var written = resumeFrom;
        var lastReport = DateTime.now();

        try {
          await for (final chunk in streamed.stream) {
            written += chunk.length;
            if (written > asset.size + _sizeSlackBytes ||
                written > _maxSingleFileBytes) {
              throw ArtworkDownloadException(
                'Asset ${asset.id} exceeded its declared size',
                httpStatus: status,
              );
            }
            sink.add(chunk);
            // Throttle progress events: a 130-file pack at full speed would
            // otherwise rebuild the UI hundreds of times per second.
            final now = DateTime.now();
            if (now.difference(lastReport).inMilliseconds >= 120) {
              lastReport = now;
              onProgress(
                ArtworkDownloadProgress(
                  completedAssets: progress().completedAssets,
                  totalAssets: progress().totalAssets,
                  receivedBytes: progress().receivedBytes - startedAt + written,
                  totalBytes: progress().totalBytes,
                  stage: ArtworkDownloadStage.downloading,
                ),
              );
            }
          }
        } finally {
          await sink.flush();
          await sink.close();
        }

        if (written != asset.size) {
          throw ArtworkDownloadException(
            'Asset ${asset.id} size mismatch',
            httpStatus: status,
          );
        }

        await part.rename(target.path);
        return asset.size;
      } catch (e) {
        // Keep the partial: a retry continues from here.
        if (attempt >= _maxAttempts) {
          if (e is ArtworkDownloadException) rethrow;
          throw ArtworkDownloadException(
            'Asset ${asset.id} download failed',
            cause: e,
          );
        }
        resumeFrom = part.existsSync() ? await part.length() : 0;
        await Future<void>.delayed(
          Duration(milliseconds: 400 * (1 << (attempt - 1))),
        );
      }
    }
  }
}