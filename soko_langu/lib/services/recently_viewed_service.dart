import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product_model.dart';
import 'product_service.dart';

/// Persists recently viewed product IDs (most recent first, capped) and
/// exposes them as a broadcast stream so the home screen can render a smart
/// "recently viewed" row that updates while the app is open.
class RecentlyViewedService {
  RecentlyViewedService._();
  static final RecentlyViewedService instance = RecentlyViewedService._();

  static const _key = 'recently_viewed_ids';
  static const _maxItems = 12;

  final StreamController<List<String>> _idsCtrl = StreamController<List<String>>.broadcast();
  final ProductService _productService = ProductService();
  List<String> _cached = const [];

  Future<List<String>> getIds() async {
    final prefs = await SharedPreferences.getInstance();
    _cached = (prefs.getStringList(_key) ?? const [])
        .where((id) => id.isNotEmpty)
        .toList();
    return _cached;
  }

  Future<void> add(String productId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_key) ?? const [];
    final updated = [productId, ...ids.where((id) => id != productId)]
        .take(_maxItems)
        .toList();
    await prefs.setStringList(_key, updated);
    _cached = updated;
    if (!_idsCtrl.isClosed) _idsCtrl.add(updated);
  }

  Stream<List<String>> watchIds() async* {
    await getIds();
    yield _cached;
    yield* _idsCtrl.stream;
  }

  Future<List<Product>> loadProducts(List<String> ids) async {
    final results = await Future.wait(ids.map((id) => _productService.getProductById(id)));
    return results.whereType<Product>().toList();
  }
}