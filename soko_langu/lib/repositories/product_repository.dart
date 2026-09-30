import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../models/product_model.dart';
import '../models/cached_product.dart';
import '../services/product_service.dart';
import '../services/product_api.dart';
import '../services/api_config.dart';
import '../services/local_cache_service.dart';
import '../services/network_state_service.dart';

/// Repository that coordinates remote (API/Postgres + Firestore) and local
/// (Hive) data sources.
///
/// **Online** → fetches from the v2 products API when [ApiConfig.kUseProductsApi]
/// is enabled (Phase C bridge), otherwise Firestore, silently updating the Hive
/// cache. The API path falls back to Firestore on failure so the feed never
/// disappears during the migration window.
/// **Offline** → falls back to the Hive cache immediately.
///
/// All public methods return a [ProductResult] so callers always know whether
/// the data came from the network or the cache.
class ProductRepository {
  final ProductService _remote;
  final ProductApiClient _api;
  final NetworkStateService? _networkState;
  StreamSubscription<List<ConnectivityResult>>? _connectSub;
  VoidCallback? _networkListener;
  bool _wasOffline = false;
  dynamic _lastDoc; // Cursor for main feed
  dynamic _brandLastDoc; // Cursor for brand filter
  dynamic _categoryLastDoc; // Cursor for category filter
  int _page = 1;
  int _brandPage = 1;
  int _categoryPage = 1;

  // Firestore `.get()` has no built-in deadline; on a dead-but-"connected"
  // radio it can retry for minutes. Capping it here makes the feed resolve to
  // the cache (or an error the UI can retry) instead of an endless skeleton.
  static const Duration _kFirestoreTimeout = Duration(seconds: 12);

  ProductRepository(
      {ProductService? remote,
      ProductApiClient? api,
      NetworkStateService? networkState})
      : _remote = remote ?? ProductService(),
        _api = api ?? ProductApiClient(),
        _networkState = networkState;

  /// Whether a network attempt is worthwhile. Prefers the central
  /// [NetworkStateService] (transport + `/health` probe); falls back to a
  /// one-shot transport check when no service was injected (tests).
  Future<bool> get isOnline async {
    if (_networkState != null) return _networkState.canAttemptNetwork;
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
    if (startOver) {
      _lastDoc = null;
      _page = 1;
    }

    if (online) {
      if (ApiConfig.kUseProductsApi) {
        try {
          // Over-fetch by one to learn whether a next page exists, then trim.
          // See ProductResult.hasMore for why the page length is not a signal.
          final res = await _api.fetchProducts(page: _page, limit: limit + 1);
          if (res.items.isNotEmpty) {
            _page++;
            final hasMore = res.items.length > limit;
            final items =
                hasMore ? res.items.sublist(0, limit) : res.items;
            await _updateCache(items);
            return ProductResult.data(
              items,
              source: DataSource.network,
              hasMore: hasMore,
            );
          }
          // API returned nothing (e.g. Postgres not yet backfilled) — fall
          // through to the Firestore source below.
        } catch (_) {}
      }
      try {
        final result = await _remote
            .fetchProducts(limit: limit, startAfter: _lastDoc)
            .timeout(_kFirestoreTimeout);
        _lastDoc = result.$2;
        await _updateCache(result.$1);
        return ProductResult.data(
          result.$1,
          source: DataSource.network,
          hasMore: result.$1.length >= limit,
        );
      } catch (_) {
        // Network failed — fall through to cache
      }
    }

    return _loadFromCache();
  }

  dynamic get lastDoc => _lastDoc;

  /// Load products for a specific brand. Pass [startOver]=true for first page.
  Future<ProductResult<List<Product>>> loadByBrand(
    String brand, {
    int limit = 30,
    bool startOver = false,
  }) async {
    if (startOver) {
      _brandLastDoc = null;
      _brandPage = 1;
    }
    final online = await isOnline;
    if (online) {
      if (ApiConfig.kUseProductsApi) {
        try {
          final res = await _api.fetchProducts(
            page: _brandPage,
            limit: limit + 1,
            brand: brand,
          );
          if (res.items.isNotEmpty) {
            _brandPage++;
            final hasMore = res.items.length > limit;
            final items = hasMore ? res.items.sublist(0, limit) : res.items;
            await _updateCache(items);
            return ProductResult.data(
              items,
              source: DataSource.network,
              hasMore: hasMore,
            );
          }
        } catch (_) {}
      }
      try {
        final result = await _remote
            .fetchProductsByBrand(
              brand,
              limit: limit,
              startAfter: _brandLastDoc,
            )
            .timeout(_kFirestoreTimeout);
        _brandLastDoc = result.$2;
        await _updateCache(result.$1);
        return ProductResult.data(
          result.$1,
          source: DataSource.network,
          hasMore: result.$1.length >= limit,
        );
      } catch (_) {}
    }
    return _loadFromCache();
  }

  /// Load products for a specific category + optional subcategory.
  /// Pass [startOver]=true for first page.
  Future<ProductResult<List<Product>>> loadProductsByCategory(
    String category, {
    String? subcategory,
    int limit = 30,
    bool startOver = false,
  }) async {
    if (startOver) {
      _categoryLastDoc = null;
      _categoryPage = 1;
    }
    final online = await isOnline;

    if (online) {
      if (ApiConfig.kUseProductsApi) {
        try {
          // Category name → Postgres uuid → server-side categoryId filter, so
          // the page shows the actual category (not a text search for its name).
          final items = await _api.fetchProductsByCategoryName(
            category,
            subcategory: subcategory,
            page: _categoryPage,
            limit: limit + 1,
          );
          if (items.isNotEmpty) {
            _categoryPage++;
            final hasMore = items.length > limit;
            final page = hasMore ? items.sublist(0, limit) : items;
            await _updateCache(page);
            return ProductResult.data(
              page,
              source: DataSource.network,
              hasMore: hasMore,
            );
          }
        } catch (_) {}
      }
      try {
        final result = await _remote
            .fetchProductsByCategory(
              category,
              subcategory: subcategory,
              limit: limit,
              startAfter: _categoryLastDoc,
            )
            .timeout(_kFirestoreTimeout);
        _categoryLastDoc = result.$2;
        await _updateCache(result.$1);
        return ProductResult.data(
          result.$1,
          source: DataSource.network,
          hasMore: result.$1.length >= limit,
        );
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
      if (ApiConfig.kUseProductsApi) {
        try {
          final product = await _api.fetchProduct(id);
          if (product != null) {
            await LocalCacheService.cacheProduct(
              CachedProduct.fromProduct(product),
            );
            return ProductResult.data(product, source: DataSource.network);
          }
        } catch (_) {}
      }
      try {
        final product = await _remote
            .fetchProduct(id)
            .timeout(_kFirestoreTimeout);
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
    if (_networkListener != null) {
      _networkState?.removeListener(_networkListener!);
      _networkListener = null;
    }
    if (_networkState != null) {
      final service = _networkState;
      _networkListener = () {
        final online = service.isOnline;
        if (online && _wasOffline) onRecovered();
        _wasOffline = !online;
      };
      service.addListener(_networkListener!);
      return;
    }
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
    if (_networkListener != null) {
      _networkState?.removeListener(_networkListener!);
      _networkListener = null;
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  Future<void> _updateCache(List<Product> products) async {
    final cached = products.map(CachedProduct.fromProduct).toList();
    await LocalCacheService.cacheProducts(cached);
  }

  /// Public cache read so callers (e.g. the feed provider) can fall back to
  /// saved listings after an overdue fetch instead of calling `loadProducts`.
  Future<ProductResult<List<Product>>> loadFromCache() => _loadFromCache();

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
  /// Whether the server has another page after this one.
  ///
  /// Computed by over-fetching one row (`limit + 1`) rather than by comparing
  /// the page length to the page size: a length check is wrong whenever a
  /// filter returns a partial page (say 17 of 30), which silently killed
  /// infinite scroll for any category between 15 and 29 products.
  final bool hasMore;
  bool get isCache => source == DataSource.cache;
  bool get isError => error != null;

  ProductResult._({
    this.data,
    this.error,
    required this.source,
    this.hasMore = false,
  });

  factory ProductResult.data(
    T data, {
    required DataSource source,
    bool hasMore = false,
  }) =>
      ProductResult._(data: data, source: source, hasMore: hasMore);

  factory ProductResult.error(String error) =>
      ProductResult._(error: error, source: DataSource.cache);
}
