import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

/// Compresses product images before upload to save Firebase bandwidth
/// and reduce storage costs.
///
/// Target: < 300KB per image, WebP format, max 1600px on longest edge.
/// 1600px, not 1200px: the product detail gallery renders full-width at ~3x
/// device pixels on phones and up to ~2400 physical px on tablets, so 1200px
/// sources looked soft (upscaled) there. The compression floor is q62 so the
/// worst case on a detailed image stays presentable in front of buyers.
/// On a 2G network (50 KB/s), a 300KB image uploads in ~6 seconds
/// vs a 5MB original which would take ~100 seconds.
class ImageCompressor {
  static const int _maxFileSize = 300 * 1024; // 300KB
  static const int _maxDimension = 1600;
  static const int _initialQuality = 90;
  static const int _minQuality = 62;

  /// Compresses an image file to under [targetBytes] (default 300KB).
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

    // Progressive compression: start at quality 90, reduce by 10 each pass
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
