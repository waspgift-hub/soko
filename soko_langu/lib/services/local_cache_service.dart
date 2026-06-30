import 'package:hive_flutter/hive_flutter.dart';
import '../models/cached_product.dart';

/// Centralised Hive initialisation and box access for offline caching.
///
/// Call [init] once during app startup (before any repository reads).
class LocalCacheService {
  LocalCacheService._();

  static const String _productBox = 'cached_products';

  static bool _initialized = false;

  /// Open all boxes and register adapters. Idempotent — safe to call multiple times.
  static Future<void> init() async {
    if (_initialized) return;

    await Hive.initFlutter();
    Hive.registerAdapter(CachedProductAdapter());

    await Hive.openBox<CachedProduct>(_productBox);
    _initialized = true;
  }

  // ---------------------------------------------------------------------------
  // Product cache
  // ---------------------------------------------------------------------------

  static Box<CachedProduct> get _products => Hive.box<CachedProduct>(_productBox);

  /// All cached products (ordered by insertion).
  static List<CachedProduct> getCachedProducts() => _products.values.toList();

  /// Replace the entire product cache with fresh data.
  static Future<void> cacheProducts(List<CachedProduct> products) async {
    await _products.clear();
    for (final p in products) {
      await _products.put(p.id, p);
    }
  }

  /// Append a single product to the cache.
  static Future<void> cacheProduct(CachedProduct product) async {
    await _products.put(product.id, product);
  }

  /// Remove stale entries.
  static Future<void> clearProducts() async => _products.clear();

  /// Number of cached products.
  static int get productCount => _products.length;
}
