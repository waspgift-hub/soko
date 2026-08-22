import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/product_model.dart';
import '../repositories/product_repository.dart';
import '../utils/network_error.dart';

/// State management for the product feed.
///
/// Uses [ProductRepository] to seamlessly serve cached data when offline.
class ProductFeedProvider extends ChangeNotifier {
  final ProductRepository _repo;

  ProductFeedProvider({ProductRepository? repo})
      : _repo = repo ?? ProductRepository();

  List<Product> _products = [];
  bool _isLoading = false;
  bool _hasMore = true;
  String? _error;
  FirestoreErrorKind? _errorKind;
  bool _fromCache = false;
  Set<String> _loadedIds = {};
  StreamSubscription<List<Product>>? _realtimeSub;

  List<Product> get products => _products;
  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;
  String? get error => _error;
  FirestoreErrorKind? get errorKind => _errorKind;
  bool get fromCache => _fromCache;

  /// Load the first page. Falls back to Hive cache if offline.
  Future<void> loadInitial() async {
    if (_isLoading) return;
    _isLoading = true;
    _error = null;
    _errorKind = null;
    notifyListeners();

    final result = await _repo.loadProducts(startOver: true);
    if (result.isError) {
      _error = result.error;
      _errorKind = FirestoreErrorKind.other;
      // Don't wipe existing products on error — keeps realtime data visible
      if (_products.isEmpty) _products = [];
    } else {
      _products = result.data ?? [];
      _fromCache = result.isCache;
      _loadedIds = _products.map((p) => p.id).toSet();
    }

    _isLoading = false;
    notifyListeners();

    // Subscribe to real-time updates (only when online)
    _startRealtimeSubscription();
  }

  void _startRealtimeSubscription() {
    _realtimeSub?.cancel();
    _realtimeSub = _repo.watchProductsRealtime().listen(
      (fresh) {
        final existingIds = _products.map((p) => p.id).toSet();
        var changed = false;

        for (final p in fresh) {
          final idx = _products.indexWhere((e) => e.id == p.id);
          if (idx >= 0) {
            // Update existing product
            _products[idx] = p;
            changed = true;
          } else if (!existingIds.contains(p.id) && !_loadedIds.contains(p.id)) {
            // New product — insert at top
            _products.insert(0, p);
            _loadedIds.add(p.id);
            changed = true;
          }
        }

        if (changed) {
          _fromCache = false;
          notifyListeners();
        }
      },
      onError: (e) {
        // Real-time stream failed silently — data is still available from the
        // initial load or cache.
        debugPrint('Realtime product stream error: $e');
      },
    );
  }

  Future<void> loadByBrand(String brand) async {
    if (_isLoading) return;
    _isLoading = true;
    _error = null;
    _errorKind = null;
    _hasMore = true;
    _loadedIds.clear();
    _currentFilter = 'brand';
    _currentBrandFilter = brand;
    notifyListeners();

    final result = await _repo.loadByBrand(brand, startOver: true);
    if (result.isError) {
      _error = result.error;
      _errorKind = FirestoreErrorKind.other;
      _products = [];
    } else {
      _products = result.data ?? [];
      _fromCache = result.isCache;
      _loadedIds = _products.map((p) => p.id).toSet();
      _hasMore = _products.length >= 15;
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadByCategory(String category, {String? subcategory}) async {
    if (_isLoading) return;
    _isLoading = true;
    _error = null;
    _errorKind = null;
    _hasMore = true;
    _loadedIds.clear();
    _currentFilter = 'category';
    _currentCategoryFilter = category;
    _currentSubcategoryFilter = subcategory;
    notifyListeners();

    final result = await _repo.loadProductsByCategory(
      category,
      subcategory: subcategory,
      startOver: true,
    );
    if (result.isError) {
      _error = result.error;
      _errorKind = FirestoreErrorKind.other;
      _products = [];
    } else {
      _products = result.data ?? [];
      _fromCache = result.isCache;
      _loadedIds = _products.map((p) => p.id).toSet();
      _hasMore = _products.length >= 15;
    }

    _isLoading = false;
    notifyListeners();
  }

  // Filter state for paginated loadMore
  String? _currentFilter;
  String? _currentBrandFilter;
  String? _currentCategoryFilter;
  String? _currentSubcategoryFilter;

  /// Load next page — works for main feed, brand, and category views.
  Future<void> loadNextPage() async {
    if (_isLoading || !_hasMore) return;
    _isLoading = true;
    _error = null;
    _errorKind = null;
    notifyListeners();

    ProductResult<List<Product>> result;

    if (_currentFilter == 'brand' && _currentBrandFilter != null) {
      result = await _repo.loadByBrand(_currentBrandFilter!);
    } else if (_currentFilter == 'category' && _currentCategoryFilter != null) {
      result = await _repo.loadProductsByCategory(
        _currentCategoryFilter!,
        subcategory: _currentSubcategoryFilter,
      );
    } else {
      result = await _repo.loadProducts();
    }

    if (result.isError) {
      _error = result.error;
      _errorKind = FirestoreErrorKind.other;
    } else {
      final fresh = result.data ?? [];
      for (final p in fresh) {
        if (!_loadedIds.contains(p.id)) {
          _loadedIds.add(p.id);
          _products.add(p);
        }
      }
      _hasMore = fresh.length >= 15;
      _fromCache = result.isCache;
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Remove a product from the in-memory list (e.g. after deletion).
  bool removeProduct(String id) {
    final before = _products.length;
    _products.removeWhere((p) => p.id == id);
    _loadedIds.remove(id);
    if (_products.length != before) {
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Pull-to-refresh — clears cache and fetches fresh data.
  Future<void> refresh() async {
    _realtimeSub?.cancel();
    _products.clear();
    _loadedIds.clear();
    _hasMore = true;
    _currentFilter = null;
    _currentBrandFilter = null;
    _currentCategoryFilter = null;
    _currentSubcategoryFilter = null;
    await loadInitial();
  }

  void onConnectivityRecovered() {
    if (_fromCache) refresh();
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    _repo.dispose();
    super.dispose();
  }
}
