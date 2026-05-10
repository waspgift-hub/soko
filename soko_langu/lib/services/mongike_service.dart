import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';

class MongikeService {
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
      return null;
    }
  }

  static Future<Map<String, dynamic>?> initiateMarketplacePayment({
    required double productPrice,
    required String productName,
    required String productId,
    required String sellerId,
    required String sellerName,
    required String email,
    required String phone,
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
        }),
      );

      if (resp.statusCode != 200) return null;

      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }
}
