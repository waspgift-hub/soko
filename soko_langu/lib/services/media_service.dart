import 'dart:io';

import 'package:image_picker/image_picker.dart';

import '../utils/network_error.dart';
import 'api_config.dart';
import 'cloudinary_service.dart';
import 'r2_media_service.dart';

/// Storage owner namespace for an upload.
///
/// The R2 key is `<kind>s/<ownerType>/<ownerId>/<uuid>.<ext>`, so this is a
/// security-relevant label: it decides which slice of the bucket a file lands
/// in and which slice the soko-media Worker will serve. Getting it wrong files
/// a seller's ID photo under `images/product/…` where listing code can reach
/// it, so every call site states its owner explicitly instead of defaulting.
enum MediaOwner {
  product('product'),
  user('user'),
  seller('seller'),
  feed('feed'),
  dispute('dispute'),
  chat('chat');

  final String wireValue;

  const MediaOwner(this.wireValue);
}

/// Single entry point for every media upload in the app.
///
/// Storage backend is chosen once, here, by [ApiConfig.kUseMediaApi]:
/// - true  -> R2 (presigned PUT straight to Cloudflare, served by soko-media
///   at `media.sokovibe.co.tz`). No third-party media host, R2 egress is free.
/// - false -> Cloudinary, kept as the rollback lever.
///
/// Both backends return a public URL and accept the same arguments, so a call
/// site never needs to know which one is live. That is the whole point of the
/// flag: previously every call site hard-coded `CloudinaryService` and
/// `kUseMediaApi` was dead code nobody could roll back to.
///
/// Failures surface as [NetworkError] with a localized message. There is
/// deliberately no silent fallback from R2 to Cloudinary: a half-migrated
/// upload path would scatter assets across two hosts, so the user is asked to
/// retry instead.
///
/// Every method takes an optional `onProgress(sent, total)` callback. It is
/// forwarded to whichever backend is active and is simply ignored by backends
/// that cannot report bytes, rather than those backends inventing a value.
class MediaService {
  static bool get _useR2 => ApiConfig.kUseMediaApi;

  static Future<String> uploadImage(
    XFile file, {
    String folder = 'soko_langu',
    MediaOwner owner = MediaOwner.product,
    MediaProgressCallback? onProgress,
  }) {
    return _useR2
        ? R2MediaService.uploadImage(
            file,
            ownerType: owner.wireValue,
            onProgress: onProgress,
          )
        : CloudinaryService.uploadImage(file, folder: folder);
  }

  static Future<String> uploadVideo(
    XFile file, {
    String folder = 'soko_langu',
    MediaOwner owner = MediaOwner.product,
    MediaProgressCallback? onProgress,
  }) {
    return _useR2
        ? R2MediaService.uploadVideo(
            file,
            ownerType: owner.wireValue,
            onProgress: onProgress,
          )
        : CloudinaryService.uploadVideo(file);
  }

  static Future<String> uploadFromPath(
    String filePath, {
    String folder = 'soko_langu',
    MediaOwner owner = MediaOwner.product,
    MediaProgressCallback? onProgress,
  }) {
    return _useR2
        ? R2MediaService.uploadFromPath(
            filePath,
            ownerType: owner.wireValue,
            onProgress: onProgress,
          )
        : CloudinaryService.uploadFromPath(filePath, folder: folder);
  }

  static Future<List<String>> uploadMultiple(
    List<XFile> files, {
    String folder = 'soko_langu',
    MediaOwner owner = MediaOwner.product,
    void Function(int index, int sent, int total)? onProgress,
  }) {
    return _useR2
        ? R2MediaService.uploadMultiple(
            files,
            ownerType: owner.wireValue,
            onProgress: onProgress,
          )
        : CloudinaryService.uploadMultiple(files, folder: folder);
  }

  /// Uploads a local file as an image, used for KYC document capture where the
  /// caller already holds a [File] rather than a picker result.
  static Future<String> uploadFileAsImage(
    File file, {
    MediaOwner owner = MediaOwner.user,
    MediaProgressCallback? onProgress,
  }) {
    return uploadImage(XFile(file.path), owner: owner, onProgress: onProgress);
  }

  /// Uploads a KYC identity document to the private store.
  ///
  /// Returns the object key, not a URL — see [R2MediaService.uploadKycImage].
  /// Kept out of [uploadImage] on purpose: identity documents must never share a
  /// code path with public marketplace media, where a mistaken flag or owner
  /// would publish a passport photo.
  static Future<String> uploadKycImage(
    XFile file, {
    MediaProgressCallback? onProgress,
  }) {
    if (!_useR2) {
      throw NetworkError(
        message: 'KYC documents require private R2 storage',
        userMessage: 'Tafadhali jaribu tena',
      );
    }
    return R2MediaService.uploadKycImage(file, onProgress: onProgress);
  }
}

/// Byte-count progress callback shared by every upload entry point.
///
/// [total] is the real size of the payload actually being sent, which for an
/// image is the *compressed* size — reporting the original would let the bar
/// stall below 100% on a large photo.
typedef MediaProgressCallback = void Function(int sent, int total);