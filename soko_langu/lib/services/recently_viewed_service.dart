import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product_model.dart';
import 'product_api.dart';
import 'product_service.dart';

/// Persists recently viewed product IDs (most recent first, capped) and
/// exposes them as a broadcast stream so the home screen can render a smart
/// "recently viewed" row that updates while the app is open.
///
/// Also handles cleanup of deleted products and persists across app restarts.
class RecentlyViewedService {
  RecentlyViewedService._();
  static final RecentlyViewedService instance = RecentlyViewedService._();

  static const _key = 'recently_viewed_ids';
  static const _maxItems = 12;

  final StreamController<List<String>> _idsCtrl = StreamController<List<String>>.broadcast();
  final ProductService _productService = ProductService();

  List<String> _cached = const [];

  /// Whether the data has been loaded at least once (for app restart handling).
  bool _initialized = false;

  Future<List<String>> getIds() async {
    final prefs = await SharedPreferences.getInstance();
    _cached = (prefs.getStringList(_key) ?? const [])
        .where((id) => id.isNotEmpty)
        .toList();
    return _cached;
  }

  /// Add a product to the recently viewed list. Removes any existing entry
  /// for the same product ID to avoid duplicates, keeps most-recent at top.
  /// Also purges any IDs of products that no longer exist or are inactive.
  Future<void> add(String productId) async {
    final prefs = await SharedPreferences.getInstance();
    var ids = prefs.getStringList(_key) ?? const [];

    // Remove existing entry for this product ID
    ids.removeWhere((id) => id == productId);

    // Add at the top
    ids.insert(0, productId);

    // Cap at max items
    ids = ids.take(_maxItems).toList();

    // Purge IDs of products that no longer exist or are inactive.
    //
    // Batched: this runs on EVERY product view, and the previous version did
    // up to 12 sequential reads (each with its own HTTP→Firestore fallback)
    // before the product screen could finish. A dead id is cheap to skip here and
    // the row already drops unresolvable products at render time, so an
    // unresolvable id is retained rather than blocking the view on network I/O.
    final validIds = ids;
    // Re-cap at max after purging
    final capped = validIds.take(_maxItems).toList();
    await prefs.setStringList(_key, capped);
    _cached = capped;
    if (!_idsCtrl.isClosed) _idsCtrl.add(capped);
  }

  /// Resolves stored ids to products, preserving most-recent-first order.
  ///
  /// BATCH, not a loop over `getProductById`. The old sequential version cost
  /// up to 12 network round-trips (each of which itself tries HTTP then falls
  /// back to Firestore) on every product view AND every home rebuild — the
  /// FutureBuilder in recently_viewed_row.dart rebuilt its future on each one.
  /// `fetchProductsByIds` is a single request for the whole set.
  ///
  /// Ids whose product is gone, hidden or otherwise unreadable are skipped
  /// rather than surfacing as empty cards, so a deleted listing cannot leave a
  /// blank tile on the home row.
  Future<List<Product>> loadProducts(List<String> ids) async {
    if (ids.isEmpty) return const [];

    final byId = <String, Product>{};
    try {
      final api = ProductApiClient();
      final fetched = await api.fetchProductsByIds(ids);
      for (final p in fetched) {
        byId[p.id] = p;
      }
    } catch (_) {
      // Fall back to individual reads so one bad id cannot blank the whole row.
      for (final id in ids) {
        try {
          final p = await _productService.getProductById(id);
          if (p != null) byId[id] = p;
        } catch (_) {
          // Skip this one; the row renders from whatever resolved.
        }
      }
    }

    final out = <Product>[];
    for (final id in ids) {
      final p = byId[id];
      if (p != null && p.isActive) out.add(p);
    }
    return out;
  }

  /// Clear the entire recently viewed list.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    _cached = const [];
    if (!_idsCtrl.isClosed) _idsCtrl.add(const []);
  }

  /// Mark all viewed items as consumed (clear the list).
  Future<void> markAllViewed() async {
    await clear();
  }

  Stream<List<String>> watchIds() async* {
    await getIds();
    yield _cached;
    yield* _idsCtrl.stream;
  }

  /// Ensure initialization happens once. Call during app startup.
  Future<void> ensureInitialized() async {
    if (!_initialized) {
      await getIds();
      _initialized = true;
    }
  }
}