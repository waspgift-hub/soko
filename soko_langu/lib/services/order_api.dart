import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../models/order_model.dart';
import 'api_config.dart';
import '../utils/network_error.dart';

/// Server-backed order lifecycle client (`/api/v1/orders`).
///
/// Phase B/C bridge: life-cycle mutations flow to the Postgres order state
/// machine instead of the legacy Firestore compat handlers. Auth is the
/// Firebase ID token (`Authorization: Bearer`); the server's `authenticate`
/// middleware resolves it to the Postgres user row via `firebaseUid`.
///
/// Envelope (server): `{ success: true, data: ... }` where list is
/// `{ orders: [...], pagination: {...} }`, detail/actions carry the order or
/// result object directly. Callers should toggle [ApiConfig.kUseOrdersApi] —
/// that flag is the migration switch, not this client.
class OrderApiClient {
  final http.Client _http;
  final Future<String?> Function() _token;

  OrderApiClient({
    http.Client? httpClient,
    Future<String?> Function()? tokenProvider,
  }) : _http = httpClient ?? http.Client(),
       _token = tokenProvider ?? _defaultToken;

  static Future<String?> _defaultToken() async =>
      FirebaseAuth.instance.currentUser?.getIdToken();

  /// `{success, data: {orders, pagination}}` for the authenticated user's
  /// orders (as buyer and/or seller). [status] filters by v2 state.
  Future<({List<OrderData> orders, int total})> fetchOrders({
    String? status,
    int page = 1,
    int limit = 20,
  }) async {
    final params = <String, String>{
      'page': '$page',
      'limit': '$limit',
      if (status != null && status.trim().isNotEmpty) 'status': status.trim(),
    };
    final uri = Uri.parse(ApiConfig.v1('/orders')).replace(queryParameters: params);
    final res = await _http
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 15));

    if (res.statusCode != 200) {
      throw _errorFor(res, action: 'fetch orders');
    }
    final data = _dataOf(res);
    final items =
        data['orders'] is List
            ? (data['orders'] as List)
                  .whereType<Map<String, dynamic>>()
                  .map(OrderData.fromApi)
                  .toList()
            : const <OrderData>[];
    final pagination =
        data['pagination'] is Map<String, dynamic>
            ? data['pagination'] as Map<String, dynamic>
            : const <String, dynamic>{};
    return (
      orders: items,
      total: (pagination['total'] as num?)?.toInt() ?? items.length,
    );
  }

  /// Fetches a single order. Returns null on 404.
  Future<OrderData?> fetchOrder(String orderId) async {
    final uri = Uri.parse(ApiConfig.v1('/orders/$orderId'));
    final res = await _http
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 15));
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw _errorFor(res, action: 'fetch order');
    }
    final data = _dataOf(res);
    if (data.isEmpty) return null;
    return OrderData.fromApi(data);
  }

  /// Seller submits a shipping quote and moves the order to
  /// `SHIPPING_FEE_SUBMITTED`. Returns the server data payload on success.
  Future<Map<String, dynamic>> submitShippingQuote(
    String orderId, {
    required int amount,
    int estimatedDays = 1,
    String? notes,
  }) async {
    final uri = Uri.parse(ApiConfig.v1('/orders/$orderId/shipping-quote'));
    final res = await _http
        .post(
          uri,
          headers: await _headers(contentType: true),
          body: jsonEncode({
            'amount': amount,
            'estimatedDays': estimatedDays,
            'notes': ?notes,
          }),
        )
        .timeout(const Duration(seconds: 15));
    return _actionResult(res, 'shipping quote');
  }

  /// Seller marks the order dispatched. Requires the order to be in
  /// `IN_ESCROW` or `READY_TO_DISPATCH` (the app's `AWAITING_ESCROW_PAYMENT`
  /// orders must be paid first).
  Future<Map<String, dynamic>> dispatchOrder(
    String orderId, {
    required String courierName,
    required String trackingNumber,
  }) async {
    final uri = Uri.parse(ApiConfig.v1('/orders/$orderId/dispatch'));
    final res = await _http
        .post(
          uri,
          headers: await _headers(contentType: true),
          body: jsonEncode({
            'courierName': courierName,
            'trackingNumber': trackingNumber,
          }),
        )
        .timeout(const Duration(seconds: 15));
    return _actionResult(res, 'dispatch');
  }

  /// Buyer confirms handover with the OTP — the OTP-gated escrow release.
  Future<Map<String, dynamic>> completeOrder(
    String orderId, {
    required String otp,
  }) async {
    final uri = Uri.parse(ApiConfig.v1('/orders/$orderId/complete'));
    final res = await _http
        .post(
          uri,
          headers: await _headers(contentType: true),
          body: jsonEncode({'otp': otp}),
        )
        .timeout(const Duration(seconds: 15));
    return _actionResult(res, 'complete');
  }

  /// Buyer-issued handover credential (`/api/v1/handover/:id/otp/issue`). The
  /// server returns the 6-digit plaintext once; it replaces the legacy
  /// Firestore `delivery_otp` read when [ApiConfig.kUseOrdersApi] is on. Only
  /// the order buyer (or an admin) may issue — see `assertCanIssueOtp`.
  Future<({String otp, DateTime? expiresAt})> issueHandoverOtp(
    String orderId,
  ) async {
    final uri = Uri.parse(ApiConfig.v1('/handover/$orderId/otp/issue'));
    final res = await _http
        .post(uri, headers: await _headers())
        .timeout(const Duration(seconds: 15));
    final data = _actionResult(res, 'otp issue');
    final otp = data['otp']?.toString() ?? '';
    if (otp.isEmpty) {
      throw NetworkError(
        message: 'Handover OTP issue returned no otp',
        userMessage: ErrorKeys.generic,
      );
    }
    DateTime? expiresAt;
    final raw = data['expiresAt']?.toString();
    if (raw != null) expiresAt = DateTime.tryParse(raw);
    return (otp: otp, expiresAt: expiresAt);
  }

  /// Buyer or seller cancels a cancellable order.
  Future<Map<String, dynamic>> cancelOrder(
    String orderId, {
    required String reason,
  }) async {
    final uri = Uri.parse(ApiConfig.v1('/orders/$orderId/cancel'));
    final res = await _http
        .post(
          uri,
          headers: await _headers(contentType: true),
          body: jsonEncode({'reason': reason}),
        )
        .timeout(const Duration(seconds: 15));
    return _actionResult(res, 'cancel');
  }

  /// Files a dispute; held escrow funds are frozen server-side.
  Future<Map<String, dynamic>> disputeOrder(
    String orderId, {
    required String reason,
    required String description,
  }) async {
    final uri = Uri.parse(ApiConfig.v1('/orders/$orderId/dispute'));
    final res = await _http
        .post(
          uri,
          headers: await _headers(contentType: true),
          body: jsonEncode({'reason': reason, 'description': description}),
        )
        .timeout(const Duration(seconds: 15));
    return _actionResult(res, 'dispute');
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  Future<Map<String, String>> _headers({bool contentType = false}) async {
    final token = await _token();
    if (token == null) {
      throw NetworkError(
        message: 'Order request requires auth',
        userMessage: ErrorKeys.sessionExpired,
      );
    }
    return {
      'Accept': 'application/json',
      if (contentType) 'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static Map<String, dynamic> _dataOf(http.Response res) {
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body is! Map<String, dynamic> || body['data'] is! Map<String, dynamic>) {
      return const <String, dynamic>{};
    }
    return body['data'] as Map<String, dynamic>;
  }

  static NetworkError _errorFor(http.Response res, {required String action}) {
    final userMessage = switch (res.statusCode) {
      401 => ErrorKeys.sessionExpired,
      403 => ErrorKeys.noPermission,
      404 => ErrorKeys.notFound,
      _ => ErrorKeys.generic,
    };
    return NetworkError(
      message: 'Order $action failed: ${res.statusCode}',
      userMessage: userMessage,
    );
  }

  static Map<String, dynamic> _actionResult(
    http.Response res,
    String action,
  ) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw _errorFor(res, action: action);
    }
    return _dataOf(res);
  }
}