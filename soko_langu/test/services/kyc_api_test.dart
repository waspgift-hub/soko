import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/services/kyc_api.dart';
import 'package:soko_vibe/utils/network_error.dart';

void main() {
  group('KycApiClient', () {
    test('fetchStatus maps envelope to kyc map', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/kyc/status/u1');
        expect(request.headers['Authorization'], 'Bearer tok');
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'kyc': {
                'fullName': 'Asha Juma',
                'idType': 'kyc_id_national',
                'idNumber': '12345678901234567890',
                'status': 'pending',
                'approved': false,
              },
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final api = KycApiClient(httpClient: client, tokenProvider: () async => 'tok');
      final result = await api.fetchStatus('u1');

      expect(result, isNotNull);
      final kyc = result!['kyc'] as Map<String, dynamic>;
      expect(kyc['fullName'], 'Asha Juma');
      expect(kyc['status'], 'pending');
      expect(kyc['approved'], false);
    });

    test('fetchStatus maps missing row to status none', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'success': true, 'data': {'kyc': {'status': 'none', 'approved': false}}}),
          200,
        ),
      );
      final api = KycApiClient(httpClient: client, tokenProvider: () async => null);
      final result = await api.fetchStatus('u1');
      final kyc = result!['kyc'] as Map<String, dynamic>;
      expect(kyc['status'], 'none');
    });

    test('fetchStatus throws NetworkError on server error', () async {
      final client = MockClient(
        (_) async => http.Response('Internal Server Error', 500),
      );
      final api = KycApiClient(httpClient: client, tokenProvider: () async => null);
      expect(() => api.fetchStatus('u1'), throwsA(isA<NetworkError>()));
    });

    test('submit posts body + bearer and maps success', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/kyc/submit');
        expect(request.headers['Authorization'], 'Bearer tok');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['fullName'], 'Asha Juma');
        expect(body['idType'], 'kyc_id_national');
        expect(body['idNumber'], '12345678901234567890');
        expect(body['idImageUrl'], 'https://cdn/img.png');
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'approved': false,
              'reason': 'Inahitaji ukaguzi wa admin',
              'message': 'KYC imewasilishwa. Subiri ukaguzi wa admin.',
            },
          }),
          200,
        );
      });

      final api = KycApiClient(httpClient: client, tokenProvider: () async => 'tok');
      final result = await api.submit(
        fullName: 'Asha Juma',
        idType: 'kyc_id_national',
        idNumber: '12345678901234567890',
        idImageUrl: 'https://cdn/img.png',
      );

      expect(result['success'], true);
      expect(result['approved'], false);
      expect(result['reason'], 'Inahitaji ukaguzi wa admin');
    });

    test('submit maps validation rejection to error shape', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'success': false,
            'error': {'code': 'VALIDATION', 'message': 'Picha ya kitambulisho haijapakiwa'},
          }),
          400,
        ),
      );
      final api = KycApiClient(httpClient: client, tokenProvider: () async => null);
      final result = await api.submit(fullName: 'Asha', idType: 'kyc_id_national', idNumber: 'x');
      expect(result['success'], false);
      expect(result['error'], 'Picha ya kitambulisho haijapakiwa');
    });
  });
}