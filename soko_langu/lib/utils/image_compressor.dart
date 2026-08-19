import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

/// Compresses product images before upload to save Firebase bandwidth
/// and reduce storage costs.
///
/// Target: < 200KB per image, WebP format, max 1200px on longest edge.
/// On a 2G network (50 KB/s), a 200KB image uploads in ~4 seconds
/// vs a 5MB original which would take ~100 seconds.
class ImageCompressor {
  static const int _maxFileSize = 200 * 1024; // 200KB
  static const int _maxDimension = 1200;
  static const int _initialQuality = 85;
  static const int _minQuality = 40;

  /// Compresses an image file to under [targetBytes] (default 200KB).
  ///
  /// Returns a new File in WebP format. The original is not modified.
  /// If the image is already under the target, it's still converted to WebP.
  static Future<File?> compressImage(
    File originalFile, {
    int targetBytes = _maxFileSize,
  }) async {
    if (!await originalFile.exists()) return null;

    final originalSize = await originalFile.length();
    if (originalSize <= targetBytes) {
      return _convertToWebP(originalFile, _initialQuality);
    }

    // Progressive compression: start at quality 85, reduce by 10 each pass
    // until we hit the target or the minimum quality.
    for (int quality = _initialQuality; quality >= _minQuality; quality -= 10) {
      final result = await _convertToWebP(originalFile, quality);
      if (result == null) continue;

      final compressedSize = await result.length();
      if (compressedSize <= targetBytes) {
        return result;
      }

      // If we're close (within 20%), stop — further compression yields
      // diminishing returns and degrades image quality noticeably.
      if (compressedSize <= targetBytes * 1.2) {
        return result;
      }

      await result.delete().catchError((_) => result);
    }

    // Last resort: return the lowest quality we have
    return _convertToWebP(originalFile, _minQuality);
  }

  /// Compresses a list of images in parallel.
  static Future<List<File>> compressImages(
    List<File> files, {
    int targetBytes = _maxFileSize,
  }) async {
    final results = await Future.wait(
      files.map((f) => compressImage(f, targetBytes: targetBytes)),
    );
    return results.whereType<File>().toList();
  }

  /// Converts an image to WebP format at the given quality.
  static Future<File?> _convertToWebP(File file, int quality) async {
    try {
      final dir = await getTemporaryDirectory();
      final baseName = file.path.split(Platform.pathSeparator).last.split('.').first;
      final outputPath = '${dir.path}${Platform.pathSeparator}${baseName}_$quality.webp';

      final result = await FlutterImageCompress.compressAndGetFile(
        file.path,
        outputPath,
        format: CompressFormat.webp,
        quality: quality,
        minWidth: _maxDimension,
        minHeight: _maxDimension,
        keepExif: false,
      );

      return result != null ? File(result.path) : null;
    } catch (e) {
      return null;
    }
  }

  /// Returns the file size in a human-readable format.
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
