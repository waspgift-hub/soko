import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/product_model.dart';
import '../models/cached_product.dart';
import '../services/product_service.dart';
import '../services/local_cache_service.dart';

/// Repository that coordinates remote (Firestore) and local (Hive) data sources.
///
/// **Online** → fetches from Firestore, silently updates the Hive cache.
/// **Offline** → falls back to the Hive cache immediately.
///
/// All public methods return a [ProductResult] so callers always know whether
/// the data came from the network or the cache.
class ProductRepository {
  final ProductService _remote;
  StreamSubscription<List<ConnectivityResult>>? _connectSub;
  bool _wasOffline = false; // Used to detect recovery from offline state
  dynamic _lastDoc; // Can be DocumentSnapshot or null

  ProductRepository({ProductService? remote})
      : _remote = remote ?? ProductService();

  /// Whether the device currently has internet.
  static Future<bool> get isOnline async {
    final results = await Connectivity().checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }

  // ---------------------------------------------------------------------------
  // Product feed (paginated)
  // ---------------------------------------------------------------------------

  /// Load products. Pass [startOver]=true for the first page (resets cursor).
  ///
  /// * Online  → Firestore query + cache update.
  /// * Offline → Hive cache (returns immediately).
  Future<ProductResult<List<Product>>> loadProducts({
    int limit = 30,
    bool startOver = false,
  }) async {
    final online = await isOnline;
    if (startOver) _lastDoc = null;

    if (online) {
      try {
        final result = await _remote.fetchProducts(limit: limit, startAfter: _lastDoc);
        _lastDoc = result.$2;
        await _updateCache(result.$1);
        return ProductResult.data(result.$1, source: DataSource.network);
      } catch (_) {
        // Network failed — fall through to cache
      }
    }

    return _loadFromCache();
  }

  dynamic get lastDoc => _lastDoc;

  /// Load products for a specific brand.
  Future<ProductResult<List<Product>>> loadByBrand(
    String brand, {
    int limit = 30,
  }) async {
    final online = await isOnline;
    if (online) {
      try {
        final products = await _remote.fetchProductsByBrand(brand, limit: limit);
        await _updateCache(products);
        return ProductResult.data(products, source: DataSource.network);
      } catch (_) {}
    }
    return _loadFromCache();
  }

  /// Load products for a specific category + optional subcategory.
  Future<ProductResult<List<Product>>> loadProductsByCategory(
    String category, {
    String? subcategory,
    int limit = 30,
  }) async {
    final online = await isOnline;

    if (online) {
      try {
        final products = await _remote.fetchProductsByCategory(
          category,
          subcategory: subcategory,
          limit: limit,
        );
        await _updateCache(products);
        return ProductResult.data(products, source: DataSource.network);
      } catch (_) {}
    }

    return _loadFromCache();
  }

  // ---------------------------------------------------------------------------
  // Single product detail
  // ---------------------------------------------------------------------------

  /// Fetch a single product by ID — tries remote first, then cache.
  Future<ProductResult<Product>> getProduct(String id) async {
    final online = await isOnline;

    if (online) {
      try {
        final product = await _remote.fetchProduct(id);
        if (product != null) {
          await LocalCacheService.cacheProduct(
            CachedProduct.fromProduct(product),
          );
          return ProductResult.data(product, source: DataSource.network);
        }
      } catch (_) {}
    }

    final cached = LocalCacheService.getCachedProducts()
        .where((p) => p.id == id)
        .firstOrNull;
    if (cached != null) {
      return ProductResult.data(
        cached.toProduct(),
        source: DataSource.cache,
      );
    }

    return ProductResult.error('Product not found');
  }

  /// Real-time stream of recent active products.
  ///
  /// Fires whenever a product is added, updated, or removed in Firestore.
  /// Used by [ProductFeedProvider] to keep the home screen live.
  /// If [brand] is provided, only products matching that brand are streamed.
  Stream<List<Product>> watchProductsRealtime({int limit = 50, String? brand}) {
    if (brand != null) {
      return _remote.getProductsByBrand(brand);
    }
    return _remote.watchProductsRealtime(limit: limit);
  }

  /// Start listening for connectivity changes. When the device comes back
  /// online after being offline, the [onRecovered] callback fires so the UI
  /// can refresh.
  void watchConnectivity(void Function() onRecovered) {
    _connectSub?.cancel();
    _connectSub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online && _wasOffline) {
        onRecovered();
      }
      _wasOffline = !online;
    });
  }

  void dispose() {
    _connectSub?.cancel();
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  Future<void> _updateCache(List<Product> products) async {
    final cached = products.map(CachedProduct.fromProduct).toList();
    await LocalCacheService.cacheProducts(cached);
  }

  Future<ProductResult<List<Product>>> _loadFromCache() async {
    final cached = LocalCacheService.getCachedProducts();
    if (cached.isEmpty) {
      return ProductResult.error('No cached data available');
    }
    return ProductResult.data(
      cached.map((c) => c.toProduct()).toList(),
      source: DataSource.cache,
    );
  }
}

// ---------------------------------------------------------------------------
// Result type
// ---------------------------------------------------------------------------

enum DataSource { network, cache }

class ProductResult<T> {
  final T? data;
  final String? error;
  final DataSource source;
  bool get isCache => source == DataSource.cache;
  bool get isError => error != null;

  ProductResult._({this.data, this.error, required this.source});

  factory ProductResult.data(T data, {required DataSource source}) =>
      ProductResult._(data: data, source: source);

  factory ProductResult.error(String error) =>
      ProductResult._(error: error, source: DataSource.cache);
}
