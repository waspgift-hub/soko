import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../models/flash_sale_model.dart';
import '../models/product_model.dart';
import 'api_config.dart';
import 'product_service.dart';

class FlashSaleService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Active flash sales stream.
  ///
  /// NOTE: We pass [now] to avoid relying on DateTime.now() at stream creation time
  /// when widgets are kept alive. Use [getActiveFlashSalesAtNow] with a fresh [now].
  Stream<List<FlashSale>> getActiveFlashSales() {
    return getActiveFlashSalesAtNow(DateTime.now());
  }

  Stream<List<FlashSale>> getActiveFlashSalesAtNow(DateTime now) {
    return _db
        .collection('flash_sales')
        .where(
          'endTime',
          isGreaterThanOrEqualTo: now.subtract(
            const Duration(hours: 1),
          ),
        )
        .snapshots()
        .map((snap) {
          try {
            return snap.docs
                .map((doc) => FlashSale.fromFirestore(doc))
                .where((s) => s.isActive && !s.isExpired && !s.isUpcoming)
                .toList()
              ..sort((a, b) => a.endTime.compareTo(b.endTime));
          } catch (e) {
            debugPrint('getActiveFlashSales parse error: $e');
            return <FlashSale>[];
          }
        })
        .handleError((e, stack) {
          debugPrint('getActiveFlashSales stream error: $e');
          debugPrint('Stack: $stack');
        });
  }


  Stream<Map<String, FlashSale>> getActiveFlashSalesMap() {
    return getActiveFlashSalesAtNow(DateTime.now()).map(
      (list) => {for (final sale in list) sale.productId: sale},
    );
  }

  Stream<Map<String, FlashSale>> getActiveFlashSalesMapAtNow(DateTime now) {
    return getActiveFlashSalesAtNow(now).map(
      (list) => {for (final sale in list) sale.productId: sale},
    );
  }


  Stream<FlashSale?> streamFlashSaleByProductId(String productId) {
    return _db
        .collection('flash_sales')
        .where('productId', isEqualTo: productId)
        .snapshots()
        .map((snap) {
      if (snap.docs.isEmpty) return null;
      final sale = FlashSale.fromFirestore(snap.docs.first);
      if (!sale.isActive || sale.isExpired) return null;
      return sale;
    });
  }

  Stream<List<FlashSale>> getMyFlashSales() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);
    return _db
        .collection('flash_sales')
        .where('sellerId', isEqualTo: user.uid)
        .snapshots()
        .map((snap) {
          try {
            return snap.docs
                .map((doc) => FlashSale.fromFirestore(doc))
                .where((s) => !s.isExpired)
                .toList()
              ..sort((a, b) => a.endTime.compareTo(b.endTime));
          } catch (e) {
            debugPrint('getMyFlashSales parse error: $e');
            return <FlashSale>[];
          }
        });
  }

  Future<Product?> getProduct(String productId) {
    return ProductService().getProductById(productId);
  }

  Future<String> createFlashSale({
    required String productId,
    required String productName,
    required String productImage,
    required double originalPrice,
    required double salePrice,
    required double discountPercent,
    required String sellerId,
    String sellerName = '',
    String sellerPhone = '',
    String location = '',
    required int stock,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    final token = await _auth.currentUser?.getIdToken();
    final resp = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/flash-sale/create'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'productId': productId,
        'productName': productName,
        'productImage': productImage,
        'originalPrice': originalPrice,
        'salePrice': salePrice,
        'discountPercent': discountPercent,
        'sellerId': sellerId,
        'sellerName': sellerName,
        'sellerPhone': sellerPhone,
        'location': location,
        'stock': stock,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
      }),
    );
    final result = jsonDecode(resp.body);
    if (result['success'] != true) {
      throw Exception(result['error'] ?? 'Failed to create flash sale');
    }
    return result['flashSaleId'] as String? ?? '';
  }

  Future<void> deleteFlashSale(String flashSaleId) async {
    await _db.collection('flash_sales').doc(flashSaleId).delete();
  }

  Future<void> triggerFlashSaleScan() async {
    try {
      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/flash-sale/scan'),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      // Server-side scan, silent fail
    }
  }

  Future<void> notifyFlashSale(FlashSale sale) async {
    try {
      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/flash-sale/notify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'productName': sale.productName,
          'salePrice': sale.salePrice,
          'discountPercent': sale.discountPercent,
          'sellerId': sale.sellerId,
        }),
      );
    } catch (e) {
      // Silent fail
    }
  }
}
