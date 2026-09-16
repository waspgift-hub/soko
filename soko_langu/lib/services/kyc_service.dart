import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'api_config.dart';
import 'kyc_api.dart';
import '../utils/network_error.dart';

class KycService {
  static Future<Map<String, dynamic>?> submitKyc({
    required String userId,
    required String fullName,
    required String idType,
    required String idNumber,
    String? idImageUrl,
    String? selfieUrl,
  }) async {
    if (ApiConfig.kUseKycApi) {
      try {
        // userId is a Firebase UID; the server keys the row off the verified
        // token, so the body needs none of the legacy Firestore fields.
        return await KycApiClient().submit(
          fullName: fullName,
          idType: idType,
          idNumber: idNumber,
          idImageUrl: idImageUrl,
          selfieUrl: selfieUrl,
        );
      } catch (e) {
        debugPrint('KycService.submitKyc (v1): $e');
        // fall through to legacy compat on transient failure
      }
    }
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/kyc/submit'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
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
      return {'success': false, 'error': translateError(e)};
    }
  }

  static Future<Map<String, dynamic>?> getKycStatus(String userId) async {
    if (ApiConfig.kUseKycApi) {
      try {
        return await KycApiClient().fetchStatus(userId);
      } catch (e) {
        debugPrint('KycService.getKycStatus (v1): $e');
        // fall through to legacy compat on transient failure
      }
    }
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      final resp = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/kyc/status/$userId'),
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );
      if (resp.statusCode != 200) return null;
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('KycService.getKycStatus: $e');
      return null;
    }
  }
}