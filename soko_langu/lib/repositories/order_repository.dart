import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/order_model.dart';
import '../services/order_api.dart';
import '../services/local_cache_service.dart';

/// OrderRepository abstracts the data source for orders.
/// It implements a Cache-Aside pattern:
/// 1. Return cached data immediately for fast UI rendering.
/// 2. Fetch fresh data from API in the background.
/// 3. Update cache and notify listeners.
class OrderRepository {
  final OrderApiClient _apiClient;

  OrderRepository({required OrderApiClient apiClient}) : _apiClient = apiClient;

  /// Fetches orders for the current user.
  /// Returns a Stream to allow the UI to handle both cached and fresh data.
  Stream<List<OrderData>> watchOrders({String? status}) async* {
    // 1. Emit cached data first
    final cached = await LocalCacheService.getCachedOrders();
    if (cached.isNotEmpty) {
      yield cached.where((o) => status == null || o.status == status).toList();
    }

    try {
      // 2. Fetch fresh data from V3 API
      final result = await _apiClient.fetchOrders(status: status);
      
      // 3. Update local cache for offline support
      await LocalCacheService.saveOrders(result.orders);
      
      yield result.orders;
    } catch (e) {
      if (cached.isEmpty) rethrow;
      // If we have cache, we silently ignore the API error or log it
    }
  }

  /// Submits a shipping quote via the V3 Server-Authoritative API.
  Future<Map<String, dynamic>> submitShippingQuote(
    String orderId, {
    required int amount,
    int estimatedDays = 1,
    String? notes,
  }) async {
    final result = await _apiClient.submitShippingQuote(
      orderId,
      amount: amount,
      estimatedDays: estimatedDays,
      notes: notes,
    );
    // Invalidate cache for this order
    await LocalCacheService.invalidateOrder(orderId);
    return result;
  }

  /// Issues a handover OTP for the buyer.
  Future<({String otp, DateTime? expiresAt})> issueHandoverOtp(String orderId) async {
    final result = await _apiClient.issueHandoverOtp(orderId);
    return result;
  }

  /// Completes order via OTP handover.
  Future<Map<String, dynamic>> completeOrder(
    String orderId, {
    required String otp,
  }) async {
    final result = await _apiClient.completeOrder(
      orderId,
      otp: otp,
    );
    await LocalCacheService.invalidateOrder(orderId);
    return result;
  }
/// Watches a single order for real-time updates (Cache-Aside).
  ///
  /// The `orders` doc supplies metadata and lifecycle status while the matching
  /// `transactions` doc supplies payment/escrow state. [OrderData.fromFirestore]
  /// merges the two so every screen reading this stream sees one canonical
  /// state instead of a buyer view and a seller view that disagree.
  Stream<OrderData> watchOrder(String orderId) async* {
    // 1. Emit the cached snapshot so the screen paints before the network.
    final cached = await LocalCacheService.getCachedOrder(orderId);
    if (cached != null) yield cached;

    // 2. Follow the authoritative doc from then on. `includeMetadataChanges` is
    // deliberately off: pending-server writes would re-emit identical orders.
    final ref = FirebaseFirestore.instance.collection('orders').doc(orderId);
    await for (final snap in ref.snapshots()) {
      // A deleted order ends the stream rather than emitting a fabricated empty
      // one — a zero-amount order would render as a real TZS 0 receipt.
      if (!snap.exists) return;
      yield OrderData.fromFirestore(snap.id, snap.data() ?? const {});
    }
  }


  /// Dispatches order.
  Future<Map<String, dynamic>> dispatchOrder(
    String orderId, {
    required String courierName,
    required String trackingNumber,
  }) async {
    final result = await _apiClient.dispatchOrder(
      orderId,
      courierName: courierName,
      trackingNumber: trackingNumber,
    );
    await LocalCacheService.invalidateOrder(orderId);
    return result;
  }
}
