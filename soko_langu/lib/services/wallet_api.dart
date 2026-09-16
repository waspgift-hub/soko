import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../models/wallet_model.dart';
import 'api_config.dart';
import '../utils/network_error.dart';

/// Seller wallet client (`/api/v1/wallet`).
///
/// Phase B/C bridge for candidate 3 (Payouts → Postgres). The Postgres
/// withdrawal core already exists server-side (`requestWithdrawal` /
/// `processWithdrawal` / `confirmPayout` with idempotency + ledger audit);
/// this client is the missing flag-gated path for the app. Money only lands in
/// this wallet once a v2 order completes, so flipping seller withdrawal UI onto
/// this client must follow the release-path converge — see the sequencing note
/// in `server/OWNERSHIP_MAP.md` §5 item 8.
///
/// Envelope (server): `{ success: true, data: ... }` where `data` is a detail
/// object for GET /, a withdrawal+wallet object for POST /withdrawals, and a
/// plain array for GET /withdrawals.
class WalletApiClient {
  final http.Client _http;
  final Future<String?> Function() _token;

  WalletApiClient({
    http.Client? httpClient,
    Future<String?> Function()? tokenProvider,
  }) : _http = httpClient ?? http.Client(),
       _token = tokenProvider ?? _defaultToken;

  static Future<String?> _defaultToken() async =>
      FirebaseAuth.instance.currentUser?.getIdToken();

  /// Seller wallet balances + recent ledger.
  Future<WalletDetail> fetchWallet() async {
    final uri = Uri.parse(ApiConfig.v1('/wallet'));
    final res = await _http
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw _errorFor(res, action: 'fetch wallet');
    }
    final data = _dataOf(res);
    if (data.isEmpty) return const WalletDetail(available: 0, pending: 0, frozen: 0, totalEarned: 0, totalWithdrawn: 0);
    return WalletDetail.fromApi(data);
  }

  /// Withdrawal history for the authenticated seller.
  Future<List<WithdrawalData>> fetchWithdrawals() async {
    final uri = Uri.parse(ApiConfig.v1('/wallet/withdrawals'));
    final res = await _http
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw _errorFor(res, action: 'fetch withdrawals');
    }
    return _listDataOf(res)
        .whereType<Map<String, dynamic>>()
        .map(WithdrawalData.fromApi)
        .toList();
  }

  /// Requests a seller withdrawal against the Postgres wallet. The server
  /// debits the ledger atomically inside the same transaction.
  Future<WithdrawalData> requestWithdrawal({
    required int amount,
    String? phoneNumber,
  }) async {
    final uri = Uri.parse(ApiConfig.v1('/wallet/withdrawals'));
    final res = await _http
        .post(
          uri,
          headers: await _headers(contentType: true),
          body: jsonEncode({
            'amount': amount,
            'phoneNumber': ?phoneNumber,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw _errorFor(res, action: 'request withdrawal');
    }
    final data = _dataOf(res);
    final withdrawal = data['withdrawal'];
    if (withdrawal is Map<String, dynamic>) {
      return WithdrawalData.fromApi(withdrawal);
    }
    return WithdrawalData.fromApi(data);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  Future<Map<String, String>> _headers({bool contentType = false}) async {
    final token = await _token();
    if (token == null) {
      throw NetworkError(
        message: 'Wallet request requires auth',
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

  static List<dynamic> _listDataOf(http.Response res) {
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body is! Map<String, dynamic> || body['data'] is! List) {
      return const [];
    }
    return body['data'] as List;
  }

  static NetworkError _errorFor(http.Response res, {required String action}) {
    final userMessage = switch (res.statusCode) {
      401 => ErrorKeys.sessionExpired,
      403 => ErrorKeys.noPermission,
      404 => ErrorKeys.notFound,
      _ => ErrorKeys.generic,
    };
    return NetworkError(
      message: 'Wallet $action failed: ${res.statusCode}',
      userMessage: userMessage,
    );
  }
}