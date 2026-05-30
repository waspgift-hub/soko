import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';

class MongikeService {
  static Future<Map<String, dynamic>?> initiateMarketplacePayment({
    required double productPrice,
    required String productName,
    required String productId,
    required String sellerId,
    required String sellerName,
    required String email,
    required String phone,
    String? buyerId,
  }) async {
    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/create-marketplace-payment-link'),
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
        }),
      );

      if (resp.statusCode != 200) return null;

      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('MongikeService initiateMarketplacePayment: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> sellerWithdraw({
    required String userId,
    required int amount,
    required String phone,
  }) async {
    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/seller/withdraw'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': userId,
          'amount': amount,
          'phone': phone,
        }),
      );

      if (resp.statusCode != 200) {
        final body = jsonDecode(resp.body);
        throw Exception(body['error'] ?? 'Withdrawal failed');
      }

      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('MongikeService sellerWithdraw: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>?> adminWithdraw({
    required String userId,
    required int amount,
    required String phone,
  }) async {
    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/withdraw'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': userId,
          'amount': amount,
          'phone': phone,
        }),
      );

      if (resp.statusCode != 200) {
        final body = jsonDecode(resp.body);
        throw Exception(body['error'] ?? 'Withdrawal failed');
      }

      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('MongikeService adminWithdraw: $e');
      rethrow;
    }
  }
}
