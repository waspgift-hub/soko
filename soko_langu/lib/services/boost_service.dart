import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'api_config.dart';
import '../utils/network_error.dart';

/// Client for the legacy `/api/boost-product` purchase flow.
///
/// The server owns boost activation: it creates a `transactions` doc of type
/// `boost`, fires a ClickPesa USSD push (or returns a BillPay control number),
/// and the collection webhook flips the product doc to `isBoosted` once the
/// payment clears. The client only starts the payment and renders the result.
class BoostService {
  // Render free tier sleeps after ~15 min idle; the first request wakes it and
  // can take up to ~60s, so escalate retries instead of failing the cold start.
  static const List<Duration> _initAttemptTimeouts = [
    Duration(seconds: 10),
    Duration(seconds: 25),
    Duration(seconds: 60),
  ];

  /// Starts a boost payment. Returns the server envelope — for USSD push it
  /// contains `message`; for BillPay it contains `billPayNumber` and
  /// `totalAmount`. Throws with a message the caller can localize.
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
    Object? lastError;
    for (var attempt = 0; attempt < _initAttemptTimeouts.length; attempt++) {
      try {
        final url = '${ApiConfig.baseUrl}/api/boost-product';
        final token = await FirebaseAuth.instance.currentUser?.getIdToken();
        debugPrint('Boost: POST $url (attempt ${attempt + 1})');
        final resp = await http.post(
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
        ).timeout(_initAttemptTimeouts[attempt]);

        debugPrint('Boost: status ${resp.statusCode} body ${resp.body}');
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        if (resp.statusCode != 200) {
          return {'error': body['error'] ?? 'Boost request failed'};
        }
        return body;
      } catch (e) {
        // Network/timeout errors during a wake-up are retried; the caller
        // renders the exception via context.trError(), which localizes it.
        lastError = e;
        final kind = classifyFirestoreError(e).kind;
        if (kind != FirestoreErrorKind.network) rethrow;
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    throw lastError ?? TimeoutException('Boost request timed out');
  }
}