import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/flash_sale_model.dart';
import '../models/product_model.dart';
import 'api_config.dart';
import 'product_service.dart';

class FlashSaleService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Stream<List<FlashSale>> getActiveFlashSales() {
    return _db
        .collection('flash_sales')
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => FlashSale.fromFirestore(doc))
            .where((s) => !s.isExpired)
            .toList()
          ..sort((a, b) => a.endTime.compareTo(b.endTime)));
  }

  Stream<List<FlashSale>> getMyFlashSales() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);
    return _db
        .collection('flash_sales')
        .where('sellerId', isEqualTo: user.uid)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => FlashSale.fromFirestore(doc))
            .where((s) => !s.isExpired)
            .toList()
          ..sort((a, b) => a.endTime.compareTo(b.endTime)));
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
    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/flash-sale/create'),
        headers: {'Content-Type': 'application/json'},
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
      if (resp.statusCode == 200 && result['success'] == true) {
        return result['flashSaleId'] as String;
      }
      throw Exception(result['error'] ?? 'Failed to create flash sale');
    } catch (e) {
      throw Exception('Failed to create flash sale: $e');
    }
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
        body: jsonEncode(sale.toMap()),
      );
    } catch (e) {
      // Silent fail
    }
  }
}
