import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:soko_vibe/models/order_model.dart';
import 'package:soko_vibe/services/order_api.dart';
import 'package:soko_vibe/utils/network_error.dart';

const _token = 'firebase-id-token';

String _envelope(Map<String, dynamic> data) => jsonEncode({
  'success': true,
  'data': data,
});

Map<String, dynamic> _orderJson() => {
  'id': 'or-1',
  'orderNumber': 'SV202609161234',
  'status': 'in_escrow',
  'buyerId': 'u-1',
  'sellerId': 'sp-1',
  'productSnapshot': {
    'id': 'p-1',
    'title': 'Vitamin C',
    'imageUrl': 'media.soko-vibe.co.tz/products/vit.jpg',
  },
  'productPrice': 50000,
  'shippingFee': 3000,
  'totalAmount': 53000,
  'platformCommission': 0,
  'courierName': 'Fikisha',
  'trackingNumber': 'FK-001',
  'createdAt': '2026-09-16T08:00:00Z',
  'buyer': {'id': 'u-1', 'displayName': 'Juma'},
  'seller': {'id': 'sp-1', 'storeName': 'Duka Bora'},
  'items': [
    {'id': 'it-1', 'productId': 'p-1', 'quantity': 2, 'unitPrice': 50000, 'totalPrice': 100000},
  ],
};

OrderApiClient _client(
  Map<String, dynamic> Function(http.Request) onRequest,
) {
  return OrderApiClient(
    tokenProvider: () async => _token,
    httpClient: MockClient((request) async {
      final data = onRequest(request);
      return http.Response(
        _envelope(data),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
}

void main() {
  group('OrderData.fromApi', () {
    test('maps the v1 order DTO', () {
      final o = OrderData.fromApi(_orderJson());
      expect(o.id, 'or-1');
      expect(o.orderNumber, 'SV202609161234');
      expect(o.status, 'in_escrow');
      expect(o.productName, 'Vitamin C');
      expect(o.productImage, 'media.soko-vibe.co.tz/products/vit.jpg');
      expect(o.productPrice, 50000);
      expect(o.shippingFee, 3000);
      expect(o.totalAmount, 53000);
      expect(o.quantity, 2);
      expect(o.courierName, 'Fikisha');
      expect(o.trackingNumber, 'FK-001');
      expect(o.buyerName, 'Juma');
      expect(o.sellerName, 'Duka Bora');
      expect(o.createdAt, DateTime.parse('2026-09-16T08:00:00Z').toLocal());
    });

    test('parses the legacy-shop snapshot shape', () {
      final o = OrderData.fromApi({
        'id': 'or-2',
        'status': 'awaiting_escrow_payment',
        'productSnapshot': {'name': 'Sofa', 'image': 'http://img/sofa.jpg', 'unitPrice': 350000},
        'productPrice': 350000,
        'createdAt': '2026-09-16T00:00:00Z',
        'buyer': {'name': 'Neema'},
        'seller': {'storeName': 'Mama Nne'},
      });
      expect(o.productName, 'Sofa');
      expect(o.productImage, 'http://img/sofa.jpg');
      expect(o.productPrice, 350000);
      expect(o.quantity, 1);
      expect(o.buyerName, 'Neema');
    });

    test('empty payload uses defaults', () {
      final o = OrderData.fromApi(const {});
      expect(o.id, '');
      expect(o.productName, '');
      expect(o.productPrice, 0);
      expect(o.totalAmount, 0);
      expect(o.quantity, 1);
      expect(o.buyerName, '');
      expect(o.createdAt, isNull);
    });
  });

  group('OrderApiClient', () {
    test('fetchOrders parses envelope and pagination', () async {
      final client = _client((request) {
        expect(request.url.path, '/api/v1/orders');
        expect(request.url.queryParameters['page'], '2');
        expect(request.url.queryParameters['status'], 'in_escrow');
        return {
          'orders': [_orderJson()],
          'pagination': {'page': 2, 'limit': 20, 'total': 7},
        };
      });
      final res = await client.fetchOrders(status: 'in_escrow', page: 2);
      expect(res.orders.length, 1);
      expect(res.total, 7);
      expect(res.orders.first.status, 'in_escrow');
    });

    test('fetchOrder returns the order detail', () async {
      final client = _client((request) {
        expect(request.url.path, '/api/v1/orders/or-1');
        return _orderJson();
      });
      final o = await client.fetchOrder('or-1');
      expect(o, isNotNull);
      expect(o!.orderNumber, 'SV202609161234');
    });

    test('fetchOrder returns null on 404', () async {
      final client = OrderApiClient(
        tokenProvider: () async => _token,
        httpClient: MockClient((request) async => http.Response('{"error":"ORDER_NOT_FOUND"}', 404)),
      );
      expect(await client.fetchOrder('missing'), isNull);
    });

    test('dispatchOrder posts to the right endpoint with the right body', () async {
      http.Request? captured;
      final client = OrderApiClient(
        tokenProvider: () async => _token,
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response(_envelope(_orderJson()), 200);
        }),
      );
      await client.dispatchOrder('or-1', courierName: 'Fikisha', trackingNumber: 'FK-99');
      expect(captured!.method, 'POST');
      expect(captured!.url.path, '/api/v1/orders/or-1/dispatch');
      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['courierName'], 'Fikisha');
      expect(body['trackingNumber'], 'FK-99');
    });

    test('cancelOrder, disputeOrder, submitShippingQuote and completeOrder post correctly', () async {
      final calls = <String>[];
      final client = OrderApiClient(
        tokenProvider: () async => _token,
        httpClient: MockClient((request) async {
          calls.add(request.url.path);
          return http.Response(_envelope({'id': 'or-1'}), 201);
        }),
      );

      await client.submitShippingQuote('or-1', amount: 4000, estimatedDays: 2);
      await client.completeOrder('or-1', otp: '123456');
      await client.cancelOrder('or-1', reason: 'Changed my mind');
      await client.disputeOrder('or-1', reason: 'Item damaged', description: 'Not as described');

      expect(calls, [
        '/api/v1/orders/or-1/shipping-quote',
        '/api/v1/orders/or-1/complete',
        '/api/v1/orders/or-1/cancel',
        '/api/v1/orders/or-1/dispute',
      ]);
    });

    test('attaches the bearer token on every call', () async {
      String? auth;
      final client = OrderApiClient(
        tokenProvider: () async => _token,
        httpClient: MockClient((request) async {
          auth = request.headers['Authorization'];
          expect(request.headers['Authorization'], 'Bearer firebase-id-token');
          return http.Response(_envelope({'orders': []}), 200);
        }),
      );
      await client.fetchOrders();
      expect(auth, 'Bearer firebase-id-token');
    });

    test('throws sessionExpired when no Firebase token is available', () async {
      final client = OrderApiClient(
        tokenProvider: () async => null,
        httpClient: MockClient((request) async => http.Response('{}', 200)),
      );
      await expectLater(
        client.fetchOrders(),
        throwsA(isA<NetworkError>().having((e) => e.userMessage, 'userMessage', ErrorKeys.sessionExpired)),
      );
    });

    test('maps 401 responses to sessionExpired', () async {
      final client = OrderApiClient(
        tokenProvider: () async => _token,
        httpClient: MockClient((request) async => http.Response('{"error":"TOKEN_EXPIRED"}', 401)),
      );
      await expectLater(
        client.fetchOrder('or-1'),
        throwsA(isA<NetworkError>().having((e) => e.userMessage, 'userMessage', ErrorKeys.sessionExpired)),
      );
    });
  });
}