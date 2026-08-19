import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'api_config.dart';
import '../utils/network_error.dart';
import '../utils/image_compressor.dart';

class CloudinaryService {
  static const String _cloudName = 'dgbsohnl4';

  static Future<Map<String, dynamic>> _getSignature({String folder = 'soko_langu'}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw NetworkError(
      message: 'Not authenticated',
      userMessage: 'Tafadhali ingia tena',
    );

    final idToken = await user.getIdToken();
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/cloudinary/sign'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({'folder': folder}),
    );

    if (response.statusCode != 200) {
      throw NetworkError(
        message: 'Failed to get upload signature',
        userMessage: 'Tafadhali jaribu tena',
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Uploads an image to Cloudinary after compressing it to WebP format.
  ///
  /// Compression happens automatically: images are resized to max 1200px,
  /// converted to WebP, and compressed to under 200KB. On a 2G network
  /// (50 KB/s), this reduces upload time from ~100s to ~4s per image.
  static Future<String> uploadImage(
    XFile xfile, {
    String folder = 'soko_langu',
  }) async {
    final sig = await _getSignature(folder: folder);

    // ── Compress before upload ──
    // Convert XFile to File, compress to WebP, then upload the compressed bytes.
    File uploadFile = File(xfile.path);
    try {
      final compressed = await ImageCompressor.compressImage(uploadFile);
      if (compressed != null) {
        uploadFile = compressed;
      }
    } catch (_) {
      // Compression failed — upload original (don't block the user)
    }

    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/$_cloudName/image/upload',
    );

    // Determine filename extension based on the (possibly compressed) file
    final ext = uploadFile.path.split('.').last;
    final request = http.MultipartRequest('POST', uri)
      ..fields['api_key'] = sig['apiKey'] as String
      ..fields['timestamp'] = sig['timestamp'].toString()
      ..fields['signature'] = sig['signature'] as String
      ..fields['folder'] = folder
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          await uploadFile.readAsBytes(),
          filename: '${DateTime.now().millisecondsSinceEpoch}.$ext',
        ),
      );

    final response = await request.send().timeout(const Duration(seconds: 30));
    final body = jsonDecode(await response.stream.bytesToString());

    // Clean up temporary compressed file
    if (uploadFile.path != xfile.path) {
      await uploadFile.delete().catchError((_) => File(''));
    }

    if (response.statusCode == 200 && body['secure_url'] != null) {
      return body['secure_url'] as String;
    }
    throw NetworkError(
      message: 'Cloudinary upload failed: ${body['error']['message'] ?? 'Unknown error'}',
      userMessage: 'Poor internet connection. Image upload failed.',
    );
  }

  static Future<String> uploadFromPath(
    String filePath, {
    String folder = 'soko_langu',
  }) async {
    final xf = XFile(filePath);
    return uploadImage(xf, folder: folder);
  }

  static Future<List<String>> uploadMultiple(
    List<XFile> xfiles, {
    String folder = 'soko_langu',
  }) async {
    final urls = <String>[];
    for (final xf in xfiles) {
      final url = await uploadImage(xf, folder: folder);
      urls.add(url);
    }
    return urls;
  }

  static Future<String> uploadVideo(
    XFile xfile, {
    String folder = 'soko_langu',
  }) async {
    final sig = await _getSignature(folder: folder);

    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/$_cloudName/video/upload',
    );

    final request = http.MultipartRequest('POST', uri)
      ..fields['api_key'] = sig['apiKey'] as String
      ..fields['timestamp'] = sig['timestamp'].toString()
      ..fields['signature'] = sig['signature'] as String
      ..fields['folder'] = folder
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          await xfile.readAsBytes(),
          filename: '${DateTime.now().millisecondsSinceEpoch}.mp4',
        ),
      );

    final response = await request.send().timeout(const Duration(seconds: 60));
    final body = jsonDecode(await response.stream.bytesToString());

    if (response.statusCode == 200 && body['secure_url'] != null) {
      return body['secure_url'] as String;
    }
    throw NetworkError(
      message: 'Cloudinary video upload failed: ${body['error']['message'] ?? 'Unknown error'}',
      userMessage: 'Poor internet connection. Video upload failed.',
    );
  }
}