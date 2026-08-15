import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/flash_sale_model.dart';
import '../models/product_model.dart';

class WidgetService {
  static const _channel = MethodChannel('soko_lang/widget');

  static Future<void> updateWidget({
    required String sales,
    required String orders,
    required String balance,
  }) async {
    try {
      await _channel.invokeMethod('updateWidget', {
        'sales': sales,
        'orders': orders,
        'balance': balance,
      });
    } catch (_) {}
  }

  /// Pushes the top trending products (optionally discounted for flash sales) to
  /// the home-screen flash-sales widget.
  static Future<void> updateFlashSales({
    required List<Product> products,
    Map<String, FlashSale>? flashSales,
  }) async {
    try {
      final items = products.take(3).map((p) {
        final sale = flashSales?.isNotEmpty == true ? flashSales![p.id] : null;
        final discounted = sale?.salePrice;
        final original = sale?.originalPrice;
        final discount = sale?.discountPercent;
        return {
          'id': p.id,
          'name': p.name,
          'price': original ?? p.price,
          'discountedPrice': discounted ?? p.price,
          'discountPercent': discount ?? 0,
          'image': p.images.isNotEmpty ? p.images.first : '',
          'currency': (p.currency != null && p.currency!.isNotEmpty) ? p.currency! : 'TZS',
        };
      }).toList();
      if (items.isEmpty) return;
      final json = jsonEncode(items);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('trending_products_data', json);
      await _channel.invokeMethod('updateFlashSales', {'trendingJson': json});
    } catch (_) {}
  }
}