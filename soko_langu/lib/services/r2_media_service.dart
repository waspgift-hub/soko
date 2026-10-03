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
/// 3. App PUTs the compressed bytes straight to the presigned URL, streaming
///    them so the caller can be told the real byte counts as they go.
/// 4. Server's CDN edge serves the object at `ApiConfig.r2PublicUrl/<key>`.
///
/// The switch stays OFF until the R2 media evidence path is live in production
/// (Phase F), then flips true bridge-by-bridge just like every other Phase flag.
class R2MediaService {
  /// Minimum gap between progress callbacks.
  ///
  /// A large video emits thousands of chunks per second; forwarding every one
  /// would rebuild a progress row per chunk and cost more than the upload
  /// itself. 120ms keeps the bar visibly moving at roughly 8 updates/second.
  static const int _progressThrottleMs = 120;

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

  /// PUT the bytes directly to the pre-signed R2 URL, reporting real byte counts.
  ///
  /// [onProgress] receives a count of bytes actually handed to the socket, and
  /// the total comes from the real file length. That is why this is a
  /// `StreamedRequest` fed through a counting transformer rather than
  /// `http.put`: `put` hands the whole body over in one call and reports
  /// nothing until the server has answered, so the only honest UI it supports
  /// is an indeterminate spinner.
  ///
  /// Retries deliberately stop at one attempt. The presigned URL is minted per
  /// upload and expires, so a blind retry against the same URL can fail in
  /// ways that look like network trouble. Callers that want a retry mint a
  /// fresh session by calling this method again.
  static Future<void> _putToR2({
    required String url,
    required File file,
    required String contentType,
    void Function(int sent, int total)? onProgress,
  }) async {
    final total = await file.length();

    final request = http.StreamedRequest('PUT', Uri.parse(url))
      ..headers['Content-Type'] = contentType
      ..contentLength = total;

    // Throttle: a video can emit thousands of chunks per second and each one
    // would otherwise rebuild a progress row.
    var lastReport = 0;
    var sent = 0;
    onProgress?.call(0, total);

    await request.sink.addStream(
      file.openRead().map((chunk) {
        sent += chunk.length;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastReport >= _progressThrottleMs || sent >= total) {
          lastReport = now;
          onProgress?.call(sent, total);
        }
        return chunk;
      }),
    );
    await request.sink.close();

    final client = http.Client();
    try {
      final response =
          await client.send(request).timeout(const Duration(seconds: 120));
      // Drain so the connection can be returned to the pool rather than left
      // half-read.
      await response.stream.drain<void>();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw NetworkError(
          message: 'R2 upload failed (HTTP ${response.statusCode})',
          userMessage: 'Tafadhali jaribu tena',
        );
      }
      // Final authoritative report: the server has confirmed the object, so the
      // full total is genuinely done regardless of chunk arithmetic.
      onProgress?.call(total, total);
    } finally {
      client.close();
    }
  }

  /// PUT a file to R2 without loading it fully into memory, reporting progress.
  ///
  /// Needed for video: a 300MB clip held as a `List<int>` needs ~300MB of
  /// heap, which a low-RAM Android device does not have while also decoding
  /// the picked video thumbnail.
  static Future<void> _putR2Stream({
    required String url,
    required File file,
    required String contentType,
    void Function(int sent, int total)? onProgress,
  }) async {
    final total = await file.length();
    final request = http.StreamedRequest('PUT', Uri.parse(url))
      ..headers['Content-Type'] = contentType
      ..contentLength = total;
    onProgress?.call(0, total);

    var lastReport = 0;
    var sent = 0;
    await request.sink.addStream(
      file.openRead().map((chunk) {
        sent += chunk.length;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastReport >= _progressThrottleMs || sent >= total) {
          lastReport = now;
          onProgress?.call(sent, total);
        }
        return chunk;
      }),
    );
    await request.sink.close();

    final client = http.Client();
    try {
      final response =
          await client.send(request).timeout(const Duration(seconds: 300));
      await response.stream.drain<void>();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw NetworkError(
          message: 'R2 upload failed (HTTP ${response.statusCode})',
          userMessage: 'Tafadhali jaribu tena',
        );
      }
      onProgress?.call(total, total);
    } finally {
      client.close();
    }
  }

/// Compresses and uploads an image to R2.
  ///
  /// Returns the public CDN URL so callers get the same shape as
  /// [CloudinaryService.uploadImage].
  ///
  /// [onProgress] receives honest phase transitions: a `preparing` report while
  /// the file is being decoded and compressed, then byte counts for the PUT
  /// itself. The compressed size is the denominator, not the original size, so
  /// the bar cannot overshoot when compression shrinks the file.
  static Future<String> uploadImage(
    XFile xfile, {
    String ownerType = 'product',
    void Function(int sent, int total)? onProgress,
  }) async {
    onProgress?.call(0, 0);

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
      ownerType: ownerType,
      ownerId: _ownerId(),
    );

    await _putToR2(
      url: session['uploadUrl']! as String,
      file: uploadFile,
      contentType: contentType,
      onProgress: onProgress,
    );

    return _publicUrl(session['key']! as String);
  }

  /// Uploads an identity document (passport/ID, selfie) to the private KYC store.
  ///
  /// Returns the object KEY, deliberately not a URL. KYC documents have no
  /// public read path at all — the media Worker refuses the `kyc/` namespace and
  /// the bucket has no public surface — so a URL here would be either dead on
  /// arrival or a leak. The app stores the key on the KYC row and asks
  /// `GET /api/v1/kyc/documents/:id/read-url` for a short-lived signed URL
  /// whenever it needs to display the document.
  static Future<String> uploadKycImage(
    XFile xfile, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final uploadFile = File(xfile.path);
    final ext = _extensionFor(uploadFile);
    final contentType = _contentTypeFor(ext);

    // No lossy compression: a reviewer has to be able to read the document, and
    // the access control here is the private bucket, not the file size.
    final session = await _createUploadSession(
      kind: 'kyc',
      contentType: contentType,
      ownerType: 'user',
      ownerId: _ownerId(),
    );

    await _putToR2(
      url: session['uploadUrl']! as String,
      file: uploadFile,
      contentType: contentType,
      onProgress: onProgress,
    );

    return session['key']! as String;
  }

/// Compresses and uploads a video to R2.
  static Future<String> uploadVideo(
    XFile xfile, {
    String ownerType = 'product',
    void Function(int sent, int total)? onProgress,
  }) async {
    final contentType = 'video/mp4';
    final session = await _createUploadSession(
      kind: 'video',
      contentType: contentType,
      ownerType: ownerType,
      ownerId: _ownerId(),
    );

    // Stream the bytes instead of readAsBytes(): a seller filming on a budget
    // phone can hand us 60-500MB, and buffering that on a mid-range Android is
    // an instant OOM kill of the app mid-upload.
    await _putR2Stream(
      url: session['uploadUrl']! as String,
      file: File(xfile.path),
      contentType: contentType,
      onProgress: onProgress,
    );

    return _publicUrl(session['key']! as String);
  }

  /// Uploads a file from a path (see CloudinaryService.uploadFromPath).
  static Future<String> uploadFromPath(
    String filePath, {
    String ownerType = 'product',
    void Function(int sent, int total)? onProgress,
  }) async {
    final xf = XFile(filePath);
    return uploadImage(xf, ownerType: ownerType, onProgress: onProgress);
  }

  /// Uploads multiple files sequentially (matches CloudinaryService.uploadMultiple).
  ///
  /// Sequential on purpose: concurrent large uploads on a mobile connection
  /// make every file slower and are the usual cause of mid-batch timeouts.
  /// Callers that want independent per-file progress should drive
  /// [TransferBatch] instead, which can also retry a single failure.
  static Future<List<String>> uploadMultiple(
    List<XFile> xfiles, {
    String ownerType = 'product',
    void Function(int index, int sent, int total)? onProgress,
  }) async {
    final urls = <String>[];
    for (var i = 0; i < xfiles.length; i++) {
      urls.add(await uploadImage(
        xfiles[i],
        ownerType: ownerType,
        onProgress: onProgress == null
            ? null
            : (sent, total) => onProgress(i, sent, total),
      ));
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
      '${ApiConfig.r2PublicUrl}/$key';

  /// Object-owner namespace segment for the R2 key.
  ///
  /// Always the caller's Firebase UID. It is deliberately NOT derived from the
  /// Cloudinary `folder` string: the R2 key layout is
  /// `<kind>s/<ownerType>/<ownerId>/…`, and folding a caller-supplied folder
  /// into the owner slot would put files under another account's namespace.
  static String _ownerId() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) return user.uid;
    // Deterministic place-holder for anonymous/dev uploads; never persisted.
    return 'dev-anon';
  }
}
