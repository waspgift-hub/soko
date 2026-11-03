import '../models/order_model.dart';
import '../services/order_api.dart';

/// Server-authoritative order repository.
///
/// Order lifecycle data is owned by the Node/Postgres API. Local product
/// caching remains separate; this repository deliberately does not invent a
/// second order cache or state machine.
class OrderRepository {
  final OrderApiClient _apiClient;

  OrderRepository({OrderApiClient? apiClient})
      : _apiClient = apiClient ?? OrderApiClient();

  Stream<List<OrderData>> watchOrders({String? status}) async* {
    final result = await _apiClient.fetchOrders(status: status);
    yield result.orders;
  }

  Future<Map<String, dynamic>> submitShippingQuote(
    String orderId, {
    required int amount,
    int estimatedDays = 1,
    String? notes,
  }) => _apiClient.submitShippingQuote(
        orderId,
        amount: amount,
        estimatedDays: estimatedDays,
        notes: notes,
      );

  Future<({String otp, DateTime? expiresAt})> issueHandoverOtp(String orderId) =>
      _apiClient.issueHandoverOtp(orderId);

  Future<Map<String, dynamic>> completeOrder(
    String orderId, {
    required String otp,
  }) => _apiClient.completeOrder(orderId, otp: otp);

  Stream<OrderData> watchOrder(String orderId) async* {
    while (true) {
      final fresh = await _apiClient.fetchOrder(orderId);
      if (fresh != null) yield fresh;
      await Future<void>.delayed(const Duration(seconds: 10));
    }
  }

  Future<Map<String, dynamic>> dispatchOrder(
    String orderId, {
    required String courierName,
    required String trackingNumber,
  }) => _apiClient.dispatchOrder(
        orderId,
        courierName: courierName,
        trackingNumber: trackingNumber,
      );
}
