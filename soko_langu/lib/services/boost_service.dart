import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'api_config.dart';

/// Client for the legacy `/api/boost-product` purchase flow.
///
/// The server owns boost activation: it creates a `transactions` doc of type
/// `boost`, fires a ClickPesa USSD push (or returns a BillPay control number),
/// and the collection webhook flips the product doc to `isBoosted` once the
/// payment clears. The client only starts the payment and renders the result.
class BoostService {
  // Render free tier sleeps after ~15 min idle; the first request wakes it and
  // can take up to ~60s, so the single attempt gets the full cold-start budget.
  static const Duration _initTimeout = Duration(seconds: 60);

  /// Starts a boost payment. Returns the server envelope — for USSD push it
  /// contains `message`; for BillPay it contains `billPayNumber` and
  /// `totalAmount`. Throws with a message the caller can localize.
  ///
  /// Deliberately single-attempt. Every POST creates a new chargeable
  /// transaction and fires a new USSD push, so retrying after a lost response
  /// would double-charge the seller. A timeout is reported as a failure and the
  /// user retries by hand, which the duplicate guard in the server dedupes.
  static Future<Map<String, dynamic>> initBoostProduct({
    required String productId,
    required String productName,
    String? productImage,
    double productPrice = 0,
    required String tier,
    required String phone,
    String paymentMethod = 'ussd_push',
    String provider = 'mpesa',
  }) async {
    final url = '${ApiConfig.baseUrl}/api/boost-product';
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    debugPrint('Boost: POST $url');
    final resp = await http
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'productId': productId,
            'productName': productName,
            'productImage': productImage ?? '',
            'productPrice': productPrice.round(),
            'tier': tier,
            'phone': phone,
            'paymentMethod': paymentMethod,
            'provider': provider,
          }),
        )
        .timeout(_initTimeout);

    debugPrint('Boost: status ${resp.statusCode} body ${resp.body}');
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    // This endpoint predates the {success} envelope and replies 200 with the
    // payment envelope directly, so gate on status plus an error field.
    if (resp.statusCode != 200 || body['error'] != null) {
      return {'error': body['error'] ?? 'Boost request failed'};
    }
    return body;
  }

  /// Outcome of waiting on a boost payment to clear.
  static const boostPaid = 'paid';
  static const boostFailed = 'failed';
  static const boostStillPending = 'pending';

  /// Polls the transaction until the collection webhook settles it.
  ///
  /// Returns [boostPaid] once the server commits `status: completed` (the same
  /// atomic batch that sets `isBoosted`), [boostFailed] on a terminal failure,
  /// or [boostStillPending] if [timeout] elapses first. Never reports success
  /// the server has not confirmed.
  static Future<String> waitForSettlement(
    String orderId, {
    Duration timeout = const Duration(minutes: 3),
    Duration interval = const Duration(seconds: 3),
  }) async {
    final deadline = DateTime.now().add(timeout);
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    while (DateTime.now().isBefore(deadline)) {
      try {
        final resp = await http
            .get(
              Uri.parse('${ApiConfig.baseUrl}/api/transaction-status/$orderId'),
              headers: {if (token != null) 'Authorization': 'Bearer $token'},
            )
            .timeout(const Duration(seconds: 15));
        if (resp.statusCode == 200) {
          final body = jsonDecode(resp.body) as Map<String, dynamic>;
          if (body['success'] == true) {
            final status = (body['status'] ?? 'pending').toString();
            if (status == 'completed') return boostPaid;
            if (status == 'failed' || status == 'cancelled') return boostFailed;
          }
        }
      } on Object catch (e) {
        // A dropped poll is not a failed payment; keep waiting until the
        // deadline so a flaky network never reports a false failure either.
        debugPrint('Boost status poll: $e');
      }
      await Future<void>.delayed(interval);
    }
    return boostStillPending;
  }
}