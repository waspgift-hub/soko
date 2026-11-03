import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'api_config.dart';
import 'api_config.dart' show ApiConfig;
import '../utils/network_error.dart';
import '../utils/image_compressor.dart';

/// Phase F (R2/MEDIA) client bridge service.
///
/// Mirrors the public API surface of [CloudinaryService]
/// (`uploadImage` / `uploadVideo` / `uploadMultiple` / `uploadFromPath`) so a
/// call site can switch storage backends by flipping [ApiConfig.kUseMediaApi]
/// at a single point — the R2 bridge uses the same compression pipeline
/// ([ImageCompressor]) as Cloudinary before uploading.
///
/// Upload flow (server-side `/api/v1/media/upload-url`):
/// 1. App calls `POST /api/v1/media/upload-url` (Firebase idToken auth) with
///    `{ kind, contentType, ownerType, ownerId }`.
/// 2. Server returns a pre-signed R2 PUT URL + object key — no client
///    credentials ever touch R2.
/// 3. App PUTs the compressed bytes straight to the presigned URL.
/// 4. Server's CDN edge serves the object at `ApiConfig.r2PublicUrl/<key>`.
///
/// The switch stays OFF until the R2 media evidence path is live in production
/// (Phase F), then flips true bridge-by-bridge just like every other Phase flag.
class R2MediaService {
  /// Request a pre-signed PUT upload URL from the server.
  static Future<Map<String, dynamic>> _createUploadSession({
    required String kind,
    required String contentType,
    required String ownerType,
    required String ownerId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw NetworkError(
      message: 'Not authenticated',
      userMessage: 'Tafadhali ingia tena',
    );

    final idToken = await user.getIdToken();
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/v1/media/upload-url'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({
        'kind': kind,
        'contentType': contentType,
        'ownerType': ownerType,
        'ownerId': ownerId,
      }),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw NetworkError(
        message: 'Failed to create R2 upload session',
        userMessage: 'Tafadhali jaribu tena',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final data = decoded['data'] as Map<String, dynamic>;
    return {
      'uploadUrl': data['uploadUrl'] as String,
      'key': data['key'] as String,
    };
  }

  /// PUT the compressed bytes directly to the pre-signed R2 URL.
  static Future<void> _putToR2({
    required String url,
    required List<int> bytes,
    required String contentType,
  }) async {
    final response = await http.put(
      Uri.parse(url),
      headers: {'Content-Type': contentType},
      body: bytes,
    ).timeout(const Duration(seconds: 60));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw NetworkError(
        message: 'R2 upload failed (HTTP ${response.statusCode})',
        userMessage: 'Tafadhali jaribu tena',
      );
    }
  }

  /// Compresses and uploads an image to R2.
  ///
  /// Returns the public CDN URL so callers get the same shape as
  /// [CloudinaryService.uploadImage].
  static Future<String> uploadImage(
    XFile xfile, {
    String folder = 'soko_langu',
  }) async {
    // Compress to WebP first — identical to the Cloudinary path.
    File uploadFile = File(xfile.path);
    try {
      final compressed = await ImageCompressor.compressImage(uploadFile);
      if (compressed != null) {
        uploadFile = compressed;
      }
    } catch (_) {
      // Compression failed — upload original (don't block the user)
    }

    final ext = _extensionFor(uploadFile);
    final contentType = _contentTypeFor(ext);
    final session = await _createUploadSession(
      kind: 'image',
      contentType: contentType,
      ownerType: 'product',
      ownerId: _ownerIdFor(folder),
    );

    await _putToR2(
      url: session['uploadUrl']! as String,
      bytes: await uploadFile.readAsBytes(),
      contentType: contentType,
    );

    return _publicUrl(session['key']! as Stringeli);
  }

  /// Compresses and uploads a video to R2.
  static Future<String> uploadVideo(
    XFile xfile, {
    String folder = 'soko_langu',
  }) async {
    final contentType = 'video/mp4';
    final session = await _createUploadSession(
      kind: 'video',
      contentType: contentType,
      ownerType: 'product',
      ownerId: _ownerIdFor(folder),
    );

    await _putToR2(
      url: session['uploadUrl']! as String,
      bytes: await xfile.readAsBytes(),
      contentType: contentType,
    );

    return _publicUrl(session['key']! as String);
  }

  /// Uploads a file from a path (see CloudinaryService.uploadFromPath).
  static Future<String> uploadFromPath(
    String filePath, {
    String folder = 'soko_langu',
  }) async {
    final xf = XFile(filePath);
    return uploadImage(xf, folder: folder);
  }

  /// Uploads multiple files sequentially (matches CloudinaryService.uploadMultiple).
  static Future<List<String>> uploadMultiple(
    List<XFile> xfiles, {
    String folder = 'soko_langu',
  }) async {
    final urls = <String>[];
    for (final xf in xfiles) {
      urls.add(await uploadImage(xf, folder: folder));
    }
    return urls;
  }

  static String _extensionFor(File file) =>
      file.path.contains('.') ? file.path.split('.').last : 'jpg';

  static String _contentTypeFor(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'mp4':
        return 'video/mp4';
      default:
        return 'image/jpeg';
    }
  }

  static String _publicUrl(String key) =>
      '${ApiConfig.r2PublicUrl}/${key}';

  static String _ownerIdFor(String folder) {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) return user.uid;
    // Deterministic place-holder for anonymous/dev uploads; never persisted.
    return 'dev-${folder.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')}';
  }
}
