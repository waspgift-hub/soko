import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/product_model.dart';
import 'api_config.dart';

class PriceDropService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<Map<String, dynamic>> createPriceDrop({
    required Product product,
    required double newPrice,
    required String aiReason,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Ingia kwanza');

    final originalPrice = product.price;
    final discount = originalPrice - newPrice;
    final discountPercent = ((discount / originalPrice) * 100).toStringAsFixed(0);

    final docRef = await _db.collection('price_drops').add({
      'productId': product.id,
      'productName': product.name,
      'productImage': product.images.isNotEmpty ? product.images.first : '',
      'sellerId': product.sellerId,
      'sellerName': product.sellerName,
      'sellerPhone': product.sellerPhone,
      'originalPrice': originalPrice,
      'newPrice': newPrice,
      'discountPercent': discountPercent,
      'currency': product.currency ?? 'TSh',
      'aiReason': aiReason,
      'createdAt': FieldValue.serverTimestamp(),
      'isActive': true,
    });

    return {
      'id': docRef.id,
      'originalPrice': originalPrice,
      'newPrice': newPrice,
      'discountPercent': discountPercent,
    };
  }

  Future<void> broadcastToAllUsers({
    required String productName,
    required double originalPrice,
    required double newPrice,
    required String discountPercent,
    required String sellerPhone,
    required String productId,
    String productImage = '',
    required String priceDropId,
  }) async {
    try {
      // Fan-out is SERVER-OWNED: Firestore rules reject client writes to other
      // users' notification rows (userId must equal request.auth.uid). The
      // server endpoint writes the in-app rows via the admin SDK, sends the
      // OneSignal push (prefs-gated), and applies a 6h per-product cooldown.
      final user = _auth.currentUser;
      final token = await user?.getIdToken();
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/price-drop/broadcast'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'priceDropId': priceDropId,
          'productName': productName,
          'originalPrice': originalPrice,
          'newPrice': newPrice,
          'discountPercent': discountPercent,
          'sellerPhone': sellerPhone,
          'productId': productId,
          'productImage': productImage,
        }),
      );
      if (resp.statusCode != 200) {
        final body = jsonDecode(resp.body);
        final msg = body['error'] ?? 'Broadcast failed';
        if (body['error'] != null && resp.statusCode == 429) {
          debugPrint('PriceDrop broadcast cooldown: $msg');
          return;
        }
      }
    } catch (e) {
      debugPrint('broadcastToAllUsers error: $e');
    }
  }

  Stream<List<Map<String, dynamic>>> getActivePriceDrops() {
    return _db
        .collection('price_drops')
        .where('isActive', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) => snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList()
          ..sort((a, b) {
            final ta = a['createdAt'];
            final tb = b['createdAt'];
            if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
            return 0;
          }));
  }
}
