import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

import 'package:soko_vibe/services/admin_dashboard_api.dart';

void main() {
  const token = 'admin-token';
  const body = {
    'success': true,
    'data': {
      'kpis': {
        'commissionRevenue': '12345',
        'commissionRevenueToday': '500',
        'commissionRevenueThisMonth': '4000',
        'commissionOrders': '12',
      },
    },
  };

  AdminDashboardApi client(
    Future<http.Response> Function(http.Request) handler,
  ) {
    return AdminDashboardApi(
      tokenProvider: () async => token,
      httpClient: http_testing.MockClient((request) async {
        expect(
          request.url.toString(),
          endsWith('/api/v1/admin/dashboard'),
        );
        expect(request.headers['Authorization'], 'Bearer $token');
        return handler(request);
      }),
    );
  }

  test('parses authoritative Decimal-string commission KPIs', () async {
    final api = client((_) async => http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
        ));

    final stats = await api.fetchCommissionStats();

    expect(stats, {
      'totalEarnings': 12345.0,
      'todayEarnings': 500.0,
      'monthlyEarnings': 4000.0,
      'totalTransactions': 12.0,
    });
  });

  test('rejects unauthorised responses instead of returning zeros', () async {
    final api = client((_) async => http.Response('{}', 403));

    expect(
      api.fetchCommissionStats(),
      throwsA(isA<HttpExceptionAdminDashboard>()),
    );
  });

  test('rejects malformed envelopes instead of returning zeros', () async {
    final api = client((_) async => http.Response(
          jsonEncode({'success': true, 'data': {}}),
          200,
          headers: {'content-type': 'application/json'},
        ));

    expect(
      api.fetchCommissionStats(),
      throwsA(isA<FormatException>()),
    );
  });

  test('requires an authenticated admin token', () async {
    final api = AdminDashboardApi(
      tokenProvider: () async => null,
      httpClient: http_testing.MockClient((_) async {
        fail('no request should be sent without a token');
      }),
    );

    expect(api.fetchCommissionStats(), throwsA(isA<StateError>()));
  });
}
