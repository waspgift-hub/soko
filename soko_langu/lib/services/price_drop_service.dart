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
  }) async {
    try {
      final users = await _db.collection('users').get();
      final batch = _db.batch();
      final List<String> fcmTokens = [];

      for (var userDoc in users.docs) {
        final notifRef = _db.collection('notifications').doc();
        batch.set(notifRef, {
          'userId': userDoc.id,
          'type': 'price_drop',
          'title': 'Punguzo Kubwa! $productName',
          'body': 'Ilishuka kutoka $originalPrice hadi $newPrice! Bonyeza kununua.',
          'productName': productName,
          'productId': productId,
          'sellerPhone': sellerPhone,
          'originalPrice': originalPrice,
          'newPrice': newPrice,
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
        final token = userDoc.data()['fcmToken'] as String?;
        if (token != null && token.isNotEmpty) {
          fcmTokens.add(token);
        }
      }

      await batch.commit();

      // Send FCM push notifications
      if (fcmTokens.isNotEmpty) {
        try {
          await http.post(
            Uri.parse('${ApiConfig.baseUrl}/api/send-bulk-notification'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'title': 'Punguzo Kubwa! $productName',
              'body': 'Ilishuka kutoka $originalPrice hadi $newPrice! Bonyeza kununua.',
              'tokens': fcmTokens,
              'data': {
                'type': 'price_drop',
                'productId': productId,
                'productName': productName,
                'sellerPhone': sellerPhone,
                'originalPrice': originalPrice.toString(),
                'newPrice': newPrice.toString(),
              },
            }),
          );
        } catch (e) {
          debugPrint('broadcastPriceDrop FCM error: $e');
        }
      }
    } catch (e) {
      debugPrint('broadcastPriceDrop error: $e');
    }
  }

  Stream<List<Map<String, dynamic>>> getActivePriceDrops() {
    return _db
        .collection('price_drops')
        .where('isActive', isEqualTo: true)
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
