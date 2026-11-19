import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

/// Authoritative commission figures from the admin dashboard endpoint.
///
/// The server computes these with a SQL SUM over settled orders. Reading the
/// Firestore `transactions` mirror here would be unbounded and would count
/// refunded or disputed orders as platform earnings.
class AdminDashboardApi {
  final http.Client _http;
  final Future<String?> Function() _token;

  AdminDashboardApi({
    http.Client? httpClient,
    Future<String?> Function()? tokenProvider,
  })  : _http = httpClient ?? http.Client(),
        _token = tokenProvider ?? _defaultToken;

  static Future<String?> _defaultToken() async =>
      FirebaseAuth.instance.currentUser?.getIdToken(true);

  /// Returns lifetime, daily and monthly commission plus the settled order
  /// count, all on the existing `PaymentService` map contract.
  Future<Map<String, double>> fetchCommissionStats() async {
    final token = await _token();
    if (token == null || token.isEmpty) {
      throw StateError('Admin sign-in is required for revenue statistics');
    }

    final res = await _http
        .get(
          Uri.parse(ApiConfig.v1('/admin/dashboard')),
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw HttpExceptionAdminDashboard(res.statusCode);
    }

    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body is! Map || body['success'] != true || body['data'] is! Map) {
      throw const FormatException('Invalid admin dashboard response');
    }
    final data = body['data'] as Map;
    if (data['kpis'] is! Map) {
      throw const FormatException('Admin dashboard KPIs are missing');
    }
    final kpis = data['kpis'] as Map;

    return {
      'totalEarnings': _decimal(kpis['commissionRevenue'], 'commissionRevenue'),
      'todayEarnings': _decimal(
        kpis['commissionRevenueToday'],
        'commissionRevenueToday',
      ),
      'monthlyEarnings': _decimal(
        kpis['commissionRevenueThisMonth'],
        'commissionRevenueThisMonth',
      ),
      'totalTransactions': _decimal(kpis['commissionOrders'], 'commissionOrders'),
    };
  }

  double _decimal(Object? raw, String key) {
    if (raw is! num && raw is! String) {
      throw FormatException('Missing admin dashboard KPI: $key');
    }
    final value = num.parse(raw.toString());
    if (!value.isFinite || value < 0) {
      throw FormatException('Invalid admin dashboard KPI: $key');
    }
    return value.toDouble();
  }
}

/// Signals that the caller is not authorised to read platform commission.
class HttpExceptionAdminDashboard implements Exception {
  const HttpExceptionAdminDashboard(this.statusCode);

  final int statusCode;

  @override
  String toString() =>
      'Admin dashboard request failed with status $statusCode';
}
