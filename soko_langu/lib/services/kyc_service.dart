import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';

class KycService {
  static Future<Map<String, dynamic>?> submitKyc({
    required String userId,
    required String fullName,
    required String idType,
    required String idNumber,
    String? idImageUrl,
    String? selfieUrl,
  }) async {
    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/kyc/submit'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': userId,
          'fullName': fullName,
          'idType': idType,
          'idNumber': idNumber,
          'idImageUrl': idImageUrl ?? '',
          'selfieUrl': selfieUrl ?? '',
        }),
      );
      if (resp.statusCode != 200) {
        final body = jsonDecode(resp.body);
        return {'success': false, 'error': body['error'] ?? 'Unknown error'};
      }
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('KycService.submitKyc: $e');
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>?> getKycStatus(String userId) async {
    try {
      final resp = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/kyc/status/$userId'),
      );
      if (resp.statusCode != 200) return null;
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('KycService.getKycStatus: $e');
      return null;
    }
  }
}