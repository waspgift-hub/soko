import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';

class CreditService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<Map<String, String>> _headers() async {
    final user = _auth.currentUser;
    final token = user == null ? null : await user.getIdToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>?> fetchBalance() async {
    try {
      final res = await http
          .get(Uri.parse(ApiConfig.v1('/ai/credits/balance')), headers: await _headers())
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      final data = body is Map<String, dynamic> ? body['data'] : null;
      return data is Map<String, dynamic> ? data : null;
    } catch (e) {
      debugPrint('[CreditService] fetchBalance failed: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> topUp(String packageId, String phone) async {
    try {
      final res = await http
          .post(
            Uri.parse(ApiConfig.v1('/ai/credits/topup')),
            headers: await _headers(),
            body: jsonEncode({'packageId': packageId, 'phone': phone}),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 201 && res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      final data = body is Map<String, dynamic> ? body['data'] : null;
      return data is Map<String, dynamic> ? data : null;
    } catch (e) {
      debugPrint('[CreditService] topUp failed: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> fetchLedger() async {
    try {
      final res = await http
          .get(Uri.parse(ApiConfig.v1('/ai/credits/ledger')), headers: await _headers())
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return const [];
      final body = jsonDecode(res.body);
      final data = body is Map<String, dynamic> ? body['data'] : null;
      if (data is List) return data.whereType<Map<String, dynamic>>().toList();
      return const [];
    } catch (e) {
      debugPrint('[CreditService] fetchLedger failed: $e');
      return const [];
    }
  }
}