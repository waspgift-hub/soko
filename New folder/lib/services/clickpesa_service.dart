import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';

class ClickPesaService {
  static int getUssdPushFee(int amount) {
    const fees = [
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
    for (final tier in fees) {
      if (amount >= tier['min']! && amount <= tier['max']!) {
        return tier['fee']!;
      }
    }
    return 7960;
  }

  static Future<Map<String, dynamic>?> initiatePayment({
    required String tier,
    required bool isYearly,
    required String email,
    required String phone,
    String userId = '',
  }) async {
    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/create-payment-link'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'tier': tier,
          'isYearly': isYearly,
          'email': email,
          'phone': phone,
          'userId': userId,
        }),
      );
      if (resp.statusCode != 200) return null;
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('ClickPesaService initiatePayment: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> initiateBoostPayment({
    required String productId,
    required String userId,
    required String phone,
  }) async {
    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/boost-product'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'productId': productId,
          'userId': userId,
          'phone': phone,
        }),
      );
      if (resp.statusCode != 200) return null;
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('ClickPesaService initiateBoostPayment: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>> initiateMarketplacePayment({
    required double productPrice,
    required String productName,
    required String productId,
    required String sellerId,
    required String sellerName,
    required String email,
    required String phone,
    String? buyerId,
    String? buyerName,
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

  static Future<Map<String, dynamic>> checkPaymentStatus(String orderId) async {
    try {
      final resp = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/payment-status/$orderId'),
        headers: {'Content-Type': 'application/json'},
      );
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      return {
        'success': resp.statusCode == 200,
        'status': body['status'] ?? 'unknown',
        'paid': body['paid'] ?? false,
        'data': body,
      };
    } catch (e) {
      debugPrint('ClickPesaService checkPaymentStatus: $e');
      return {
        'success': false,
        'status': 'error',
        'paid': false,
        'error': e.toString(),
      };
    }
  }

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

  static Future<Map<String, dynamic>?> initiateWithdrawal({
    required String userId,
    required int amount,
    required String phone,
  }) async {
    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/withdraw'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': userId, 'amount': amount, 'phone': phone}),
      );
      if (resp.statusCode != 200) {
        final body = jsonDecode(resp.body);
        throw Exception(body['error'] ?? 'Withdrawal failed');
      }
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('ClickPesaService initiateWithdrawal: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>?> streamerWithdraw({
    required String userId,
    required int amount,
    required String phone,
  }) async {
    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/streamer/withdraw'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': userId, 'amount': amount, 'phone': phone}),
      );
      if (resp.statusCode != 200) {
        final body = jsonDecode(resp.body);
        throw Exception(body['error'] ?? 'Withdrawal failed');
      }
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('ClickPesaService streamerWithdraw: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> adminWithdraw({
    required String userId,
    required int amount,
    required String phone,
  }) async {
    final resp = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/admin/withdraw'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': userId, 'amount': amount, 'phone': phone}),
    );
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode != 200) {
      throw Exception(body['error'] ?? 'Withdrawal failed');
    }
    return body;
  }

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
}
