import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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
  final LocalCacheService _cache;

  OrderRepository({
    required OrderApiClient apiClient,
    required LocalCacheService cache,
  }) : _apiClient = apiClient,
       _cache = cache;

  /// Fetches orders for the current user.
  /// Returns a Stream to allow the UI to handle both cached and fresh data.
  Stream<List<OrderData>> watchOrders({String? status}) async* {
    // 1. Emit cached data first
    final cached = await _cache.getCachedOrders();
    if (cached.isNotEmpty) {
      yield cached.where((o) => status == null || o.status == status).toList();
    }

    try {
      // 2. Fetch fresh data from V3 API
      final result = await _apiClient.fetchOrders(status: status);
      
      // 3. Update local cache for offline support
      await _cache.saveOrders(result.orders);
      
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
    await _cache.invalidateOrder(orderId);
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
    await _cache.invalidateOrder(orderId);
    return result;
  }

  /// Watches a single order for real-time updates (Cache-Aside).
  Stream<OrderData> watchOrder(String orderId) async* {
    // 1. Emit cached version
    final cached = await _cache.getCachedOrder(orderId);
    if (cached != null) yield cached;

    // 2. Poll API for fresh state (since API is HTTP, not WebSocket)
    while (true) {
      try {
        final fresh = await _apiClient.fetchOrder(orderId);
        if (fresh != null) {
          await _cache.saveOrder(fresh);
          yield fresh;
        }
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 10));
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
    await _cache.invalidateOrder(orderId);
    return result;
  }
}
