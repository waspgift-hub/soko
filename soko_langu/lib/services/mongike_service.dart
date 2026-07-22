import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import '../utils/network_error.dart';

class MongikeService {
  MongikeService._();
  static final MongikeService instance = MongikeService._();

  static Future<Map<String, String>> _authHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, dynamic>> initiateMarketplacePayment({
    required double productPrice,
    String? productName,
    String? productId,
    String? sellerId,
    String? sellerName,
    String? email,
    required String phone,
    String? buyerId,
    String? deliveryType,
    double? shippingCost,
    String? existingTransactionId,
    String? description,
    String? productImage,
  }) async {
    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/create-marketplace-payment-link'),
        headers: await _authHeaders(),
        body: jsonEncode({
          'productPrice': productPrice,
          'productName': productName,
          'productId': productId,
          'sellerId': sellerId,
          'sellerName': sellerName,
          'email': email,
          'phone': phone,
          'buyerId': buyerId,
          'deliveryType': deliveryType ?? 'local',
          'shippingCost': shippingCost ?? 0,
          'existingTransactionId': existingTransactionId,
          'productImage': productImage,
        }),
      );
      final body = jsonDecode(resp.body);
      if (resp.statusCode != 200) {
        return {
          'error':
              body['error'] ?? body['message'] ?? 'Payment initiation failed',
        };
      }
      return body as Map<String, dynamic>;
    } catch (e) {
      return {'error': translateError(e)};
    }
  }

  static Future<Map<String, dynamic>> adminWithdraw({
    required double amount,
    required String phone,
    String? userId,
  }) async {
    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/create-payout'),
        headers: await _authHeaders(),
        body: jsonEncode({
          'amount': amount,
          'phone': phone,
          'userId': userId ?? '',
          'type': 'admin',
        }),
      );
      final body = jsonDecode(resp.body);
      if (resp.statusCode != 200) {
        return {'error': body['error'] ?? 'Withdrawal failed'};
      }
      return body as Map<String, dynamic>;
    } catch (e) {
      return {'error': translateError(e)};
    }
  }

  static Future<Map<String, dynamic>> sellerWithdraw({
    required double amount,
    required String phone,
    String? userId,
  }) async {
    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/create-payout'),
        headers: await _authHeaders(),
        body: jsonEncode({
          'amount': amount,
          'phone': phone,
          'userId': userId ?? '',
          'type': 'seller',
        }),
      );
      final body = jsonDecode(resp.body);
      if (resp.statusCode != 200) {
        return {'error': body['error'] ?? 'Withdrawal failed'};
      }
      return body as Map<String, dynamic>;
    } catch (e) {
      return {'error': translateError(e)};
    }
  }

  static Future<bool> verifyPayment(String reference) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('transactions')
          .doc(reference)
          .get();
      if (!doc.exists) return false;
      final status = doc.data()?['status'] as String? ?? '';
      return status == 'completed';
    } catch (_) {
      return false;
    }
  }
}
