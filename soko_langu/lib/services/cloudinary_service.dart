import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../utils/network_error.dart';

class CloudinaryService {
  static const String _cloudName = 'dgbsohnl4';
  static const String _uploadPreset = 'ecommerce';

  static Future<String> uploadImage(
    XFile xfile, {
    String folder = 'soko_langu',
  }) async {
    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/$_cloudName/image/upload',
    );

    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = _uploadPreset
      ..fields['folder'] = folder
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          await xfile.readAsBytes(),
          filename: '${DateTime.now().millisecondsSinceEpoch}.jpg',
        ),
      );

    final response = await request.send().timeout(const Duration(seconds: 30));
    final body = jsonDecode(await response.stream.bytesToString());

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
    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/$_cloudName/video/upload',
    );

    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = _uploadPreset
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
