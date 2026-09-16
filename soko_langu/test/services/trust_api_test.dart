import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

import 'package:soko_vibe/services/trust_api.dart';

void main() {
  group('TrustApiClient', () {
    http.Client makeClient(
      Map<String, dynamic> body, {
      int statusCode = 200,
    }) {
      return http_testing.MockClient((request) async {
        return http.Response(
          jsonEncode(body),
          statusCode,
          headers: {'content-type': 'application/json'},
        );
      });
    }

    test('fetchPassport parses the passport envelope', () async {
      final client = makeClient({
        'success': true,
        'data': {
          'seller': {
            'id': 'sp-1',
            'storeName': 'Duka Bora',
            'reliabilityScore': 92,
            'verificationStatus': 'verified',
          },
          'metrics': {
            'totalOrders': 40,
            'completedOrders': 38,
            'onTimeDispatches': 36,
            'activeDisputes': 1,
          },
          'indicators': [
            {'key': 'identity_verified', 'level': 'green'},
            {'key': 'fulfillment', 'value': 95, 'level': 'green'},
          ],
        },
      });

      final api = TrustApiClient(
        httpClient: client,
        tokenProvider: () async => 'test-token',
      );

      final result = await api.fetchPassport('firebase-uid-123');

      expect(result, isNotNull);
      expect(result!['seller'], isA<Map>());
      expect((result['seller'] as Map)['storeName'], 'Duka Bora');
      expect((result['indicators'] as List).length, 2);
    });

    test('fetchPassport returns null on 404', () async {
      final client = makeClient(
        {'success': false, 'error': {'code': 'SELLER_NOT_FOUND'}},
        statusCode: 404,
      );

      final api = TrustApiClient(
        httpClient: client,
        tokenProvider: () async => 'test-token',
      );

      final result = await api.fetchPassport('missing-seller');
      expect(result, isNull);
    });

    test('fetchPassport returns null on 500 without throwing', () async {
      final client = makeClient(
        {'success': false},
        statusCode: 500,
      );

      final api = TrustApiClient(
        httpClient: client,
        tokenProvider: () async => 'test-token',
      );

      final result = await api.fetchPassport('firebase-uid-123');
      expect(result, isNull);
    });

    test('fetchPassport tolerates a null token (optionalAuth endpoint)', () async {
      final client = makeClient({
        'success': true,
        'data': {'seller': {'storeName': 'Duka'}, 'indicators': []},
      });

      final api = TrustApiClient(
        httpClient: client,
        tokenProvider: () async => null,
      );

      final result = await api.fetchPassport('firebase-uid-123');
      expect(result, isNotNull);
    });
  });
}