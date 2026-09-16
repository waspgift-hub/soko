import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:soko_vibe/models/wallet_model.dart';
import 'package:soko_vibe/services/wallet_api.dart';
import 'package:soko_vibe/utils/network_error.dart';

const _token = 'firebase-id-token';

String _envelope(Object data) => jsonEncode({'success': true, 'data': data});

Map<String, dynamic> _walletJson() => {
  'wallet': {'id': 'w-1', 'sellerId': 'sp-1'},
  'balances': {
    'available': '85000',
    'pending': '0',
    'frozen': '0',
    'totalEarned': '200000',
    'totalWithdrawn': '115000',
  },
  'ledgerBalance': '85000',
  'ledger': [
    {
      'id': 'le-1',
      'walletId': 'w-1',
      'type': 'ORDER_SETTLEMENT',
      'amount': '80000',
      'balanceAfter': '85000',
      'referenceType': 'order',
      'referenceId': 'or-9',
      'idempotencyKey': 'settlement_or-9',
      'description': 'Order settlement from escrow release',
      'createdAt': '2026-09-16T08:00:00Z',
    },
  ],
  'pagination': {'page': 1, 'limit': 20, 'total': 1},
};

Map<String, dynamic> _withdrawalJson() => {
  'id': 'wd-1',
  'walletId': 'w-1',
  'sellerId': 'sp-1',
  'amount': 30000,
  'provider': 'clickpesa',
  'status': 'pending',
  'idempotencyKey': 'withdrawal_sp-1_1726400000000',
  'createdAt': '2026-09-16T09:00:00Z',
};

WalletApiClient _client(
  Future<http.Response> Function(http.Request) handler,
) {
  return WalletApiClient(
    tokenProvider: () async => _token,
    httpClient: MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer $_token',
          reason: 'every wallet call must authenticate');
      return handler(request);
    }),
  );
}

void main() {
  group('WalletDetail.fromApi', () {
    test('parses string money values (Prisma Decimal serialization)', () {
      final w = WalletDetail.fromApi(_walletJson());
      expect(w.available, 85000);
      expect(w.pending, 0);
      expect(w.totalEarned, 200000);
      expect(w.totalWithdrawn, 115000);
      expect(w.ledger, hasLength(1));
      final entry = w.ledger.first;
      expect(entry.type, 'ORDER_SETTLEMENT');
      expect(entry.amount, 80000);
      expect(entry.balanceAfter, 85000);
      expect(entry.referenceId, 'or-9');
      expect(entry.createdAt, DateTime.parse('2026-09-16T08:00:00Z'));
    });

    test('tolerates numeric money values from other clients', () {
      final w = WalletDetail.fromApi({
        'balances': {'available': 500, 'pending': 0, 'frozen': 0, 'totalEarned': 500, 'totalWithdrawn': 0},
        'ledger': [],
      });
      expect(w.available, 500);
    });
  });

  group('WithdrawalData.fromApi', () {
    test('parses the withdrawal DTO', () {
      final w = WithdrawalData.fromApi(_withdrawalJson());
      expect(w.id, 'wd-1');
      expect(w.amount, 30000);
      expect(w.status, 'pending');
      expect(w.providerPayoutId, isNull);
    });
  });

  group('WalletApiClient.fetchWallet', () {
    test('GET /api/v1/wallet returns balances', () async {
      final client = _client((req) async {
        expect(req.method, 'GET');
        expect(req.url.path, '/api/v1/wallet');
        return http.Response(_envelope(_walletJson()), 200,
            headers: {'content-type': 'application/json'});
      });
      final wallet = await client.fetchWallet();
      expect(wallet.available, 85000);
      expect(wallet.ledger.single.type, 'ORDER_SETTLEMENT');
    });

    test('empty envelope maps to a zeroed wallet without throwing', () async {
      final client = _client((req) async => http.Response(_envelope(<String, dynamic>{}), 200,
          headers: {'content-type': 'application/json'}));
      final wallet = await client.fetchWallet();
      expect(wallet.available, 0);
      expect(wallet.ledger, isEmpty);
    });

    test('401 surfaces sessionExpired', () async {
      final client = _client((req) async => http.Response('{"error":"TOKEN_EXPIRED"}', 401));
      await expectLater(
        client.fetchWallet(),
        throwsA(isA<NetworkError>().having((e) => e.userMessage, 'userMessage', ErrorKeys.sessionExpired)),
      );
    });
  });

  group('WalletApiClient.fetchWithdrawals', () {
    test('GET /api/v1/wallet/withdrawals LIST envelope parses rows', () async {
      final client = _client((req) async {
        expect(req.method, 'GET');
        expect(req.url.path, '/api/v1/wallet/withdrawals');
        return http.Response(_envelope([_withdrawalJson()]), 200,
            headers: {'content-type': 'application/json'});
      });
      final rows = await client.fetchWithdrawals();
      expect(rows, hasLength(1));
      expect(rows.single.amount, 30000);
      expect(rows.single.status, 'pending');
    });
  });

  group('WalletApiClient.requestWithdrawal', () {
    test('POST sends amount + optional phone and returns the withdrawal', () async {
      final client = _client((req) async {
        expect(req.method, 'POST');
        expect(req.url.path, '/api/v1/wallet/withdrawals');
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['amount'], 30000);
        expect(body['phoneNumber'], '+255712345678');
        return http.Response(_envelope({'withdrawal': _withdrawalJson(), 'wallet': {'id': 'w-1'}}), 201,
            headers: {'content-type': 'application/json'});
      });
      final w = await client.requestWithdrawal(amount: 30000, phoneNumber: '+255712345678');
      expect(w.id, 'wd-1');
      expect(w.amount, 30000);
    });

    test('201 without a withdrawal key still parses the echoed withdrawal', () async {
      final client = _client((req) async => http.Response(_envelope(_withdrawalJson()), 201,
          headers: {'content-type': 'application/json'}));
      final w = await client.requestWithdrawal(amount: 30000);
      expect(w.status, 'pending');
    });

    test('400 INSUFFICIENT_BALANCE surfaces as generic', () async {
      final client = _client((req) async => http.Response('{"error":"INSUFFICIENT_BALANCE"}', 400));
      await expectLater(
        client.requestWithdrawal(amount: 999999999),
        throwsA(isA<NetworkError>().having((e) => e.message, 'message', contains('request withdrawal'))),
      );
    });
  });
}