import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'api_config.dart';

class ClickPesaService {
  static const List<Map<String, int>> _ussdPushFeeTiers = [
    { 'min': 500, 'max': 999, 'fee': 54 },
    { 'min': 1000, 'max': 1999, 'fee': 92 },
    { 'min': 2000, 'max': 2999, 'fee': 124 },
    { 'min': 3000, 'max': 3999, 'fee': 230 },
    { 'min': 4000, 'max': 4999, 'fee': 380 },
    { 'min': 5000, 'max': 9999, 'fee': 580 },
    { 'min': 10000, 'max': 19999, 'fee': 920 },
    { 'min': 20000, 'max': 39999, 'fee': 1150 },
    { 'min': 40000, 'max': 49999, 'fee': 1572 },
    { 'min': 50000, 'max': 99999, 'fee': 2136 },
    { 'min': 100000, 'max': 199999, 'fee': 3240 },
    { 'min': 200000, 'max': 299999, 'fee': 3660 },
    { 'min': 300000, 'max': 399999, 'fee': 4080 },
    { 'min': 400000, 'max': 499999, 'fee': 4340 },
    { 'min': 500000, 'max': 599999, 'fee': 4820 },
    { 'min': 600000, 'max': 799999, 'fee': 5230 },
    { 'min': 800000, 'max': 999999, 'fee': 6146 },
    { 'min': 1000000, 'max': 1999999, 'fee': 7210 },
    { 'min': 2000000, 'max': 3000000, 'fee': 7960 },
  ];

  static int getUssdPushFee(int amount) {
    for (final tier in _ussdPushFeeTiers) {
      if (amount >= tier['min']! && amount <= tier['max']!) {
        return tier['fee']!;
      }
    }
    return 7960;
  }

  // ─── Payin (Collection) ───

  static Future<Map<String, dynamic>?> initiateMarketplacePayment({
    required double productPrice,
    required String productName,
    required String productId,
    required String sellerId,
    required String sellerName,
    required String email,
    required String phone,
    String? buyerId,
    String? buyerName,
    String deliveryType = 'local',
  }) async {
    try {
      final url = '${ApiConfig.baseUrl}/api/create-marketplace-payment-link';
      debugPrint('ClickPesa: POST $url');
      final resp = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'productPrice': productPrice,
          'productName': productName,
          'productId': productId,
          'sellerId': sellerId,
          'sellerName': sellerName,
          'email': email,
          'phone': phone,
          'buyerId': buyerId ?? '',
          'buyerName': buyerName ?? '',
          'deliveryType': deliveryType,
        }),
      );

      debugPrint('ClickPesa: status ${resp.statusCode} body ${resp.body}');
      if (resp.statusCode != 200) {
        debugPrint('ClickPesa: non-200 response');
        return {'error': resp.body};
      }

      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('ClickPesaService initiateMarketplacePayment: $e');
      return {'error': 'Network error: $e'};
    }
  }

  // ─── Payout (Withdrawal) ───

  static Future<Map<String, dynamic>> sellerWithdraw({
    required String userId,
    required int amount,
    required String phone,
  }) async {
    final resp = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/seller/withdraw'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': userId, 'amount': amount, 'phone': phone}),
    );
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode != 200) {
      throw Exception(body['error'] ?? 'Withdrawal failed');
    }
    return body;
  }

  static Future<Map<String, dynamic>> adminWithdraw({
    required String userId,
    required int amount,
    required String phone,
  }) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    final resp = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/admin/withdraw'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'userId': userId, 'amount': amount, 'phone': phone}),
    );
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode != 200) {
      throw Exception(body['error'] ?? 'Withdrawal failed');
    }
    return body;
  }

  static Future<Map<String, dynamic>> createPayout({
    required String userId,
    required int amount,
    required String phone,
    String? type,
    String? source,
  }) async {
    final resp = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/create-payout'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'userId': userId,
        'amount': amount,
        'phone': phone,
        'type': type ?? 'manual',
        'source': source,
      }),
    );
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode != 200) {
      throw Exception(body['error'] ?? 'Payout failed');
    }
    return body;
  }

  static Future<Map<String, dynamic>?> getPayoutStatus(String payoutId) async {
    try {
      final resp = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/payout-status/$payoutId'),
      );
      if (resp.statusCode != 200) return null;
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('getPayoutStatus: $e');
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> getPayouts({
    String? userId,
    int limit = 50,
  }) async {
    try {
      final params = <String, String>{'limit': limit.toString()};
      if (userId != null) params['userId'] = userId;
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/payouts')
          .replace(queryParameters: params);
      final resp = await http.get(uri);
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return (data['payouts'] as List?)
              ?.cast<Map<String, dynamic>>() ??
          [];
    } catch (e) {
      debugPrint('getPayouts: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>> retryPayout(String payoutId) async {
    final resp = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/payout/retry/$payoutId'),
      headers: {'Content-Type': 'application/json'},
    );
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode != 200) {
      throw Exception(body['error'] ?? 'Retry failed');
    }
    return body;
  }

  static Future<Map<String, dynamic>?> getFinanceSummary() async {
    try {
      final resp = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/finance-summary'),
        headers: {'Content-Type': 'application/json'},
      );
      if (resp.statusCode != 200) return null;
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('ClickPesaService getFinanceSummary: $e');
      return null;
    }
  }

  // ─── Balance & Preview ───

  static Future<int> getBalance() async {
    try {
      final resp = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/clickpesa/balance'),
      );
      if (resp.statusCode != 200) return 0;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return (data['balance'] as num).toInt();
    } catch (e) {
      debugPrint('getBalance: $e');
      return 0;
    }
  }

  static Future<Map<String, dynamic>?> payoutPreview({
    required int amount,
    required String phone,
  }) async {
    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/clickpesa/payout-preview'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'amount': amount, 'phone': phone}),
      );
      if (resp.statusCode != 200) return null;
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('payoutPreview: $e');
      return null;
    }
  }
}