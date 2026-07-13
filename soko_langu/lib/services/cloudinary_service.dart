import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'api_config.dart';
import '../utils/network_error.dart';

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

  static Future<String> uploadImage(
    XFile xfile, {
    String folder = 'soko_langu',
  }) async {
    final sig = await _getSignature(folder: folder);

    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/$_cloudName/image/upload',
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