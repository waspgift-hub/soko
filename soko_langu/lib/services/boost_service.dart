import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../models/boost_tier.dart';
import 'api_config.dart';

class BoostService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<Map<String, String>> _authHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>?> initiateBoostPayment({
    required String productId,
    required BoostTier tier,
    required String phone,
    required String userId,
    String productName = '',
    String productImage = '',
    int productPrice = 0,
  }) async {
    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/boost-product'),
        headers: await _authHeaders(),
        body: jsonEncode({
          'productId': productId,
          'tier': tier.name,
          'amount': tier.priceTzs,
          'durationDays': tier.durationDays,
          'phone': phone,
          'userId': userId,
          'productName': productName,
          'productImage': productImage,
          'productPrice': productPrice,
        }),
      );

      if (resp.statusCode != 200) {
        try {
          final body = jsonDecode(resp.body);
          throw Exception(
            body['error'] ?? body['message'] ?? 'Boost payment failed',
          );
        } on FormatException {
          throw Exception(
            'Server error (${resp.statusCode}). Tafadhali jaribu tena.',
          );
        }
      }

      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('BoostService initiateBoostPayment: $e');
      rethrow;
    }
  }

  Future<void> handleBoostPaymentSuccess({
    required String productId,
    required BoostTier tier,
  }) async {
    try {
      final now = DateTime.now();
      final boostedUntil = now.add(Duration(days: tier.durationDays));

      await _db.collection('products').doc(productId).update({
        'isBoosted': true,
        'boostedUntil': Timestamp.fromDate(boostedUntil),
        'boostTier': tier.name,
        'isFeatured': true,
        'featuredUntil': Timestamp.fromDate(boostedUntil),
      });
    } catch (e) {
      debugPrint('BoostService handleBoostPaymentSuccess: $e');
      rethrow;
    }
  }

  Future<void> notifyBoost({
    required String productId,
    required String tierName,
    String? sellerId,
  }) async {
    try {
      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/boost/notify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'productId': productId,
          'tier': tierName,
          'sellerId': sellerId ?? '',
        }),
      );
    } catch (e) {
      debugPrint('BoostService notifyBoost: $e');
    }
  }

  static int getPriceForTier(BoostTier tier) => tier.priceTzs;

  static int getDurationForTier(BoostTier tier) => tier.durationDays;
}
