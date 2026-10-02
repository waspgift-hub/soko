import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'api_config.dart';
import '../utils/network_error.dart';

/// Fee ClickPesa quoted for one payment method on a USSD push.
class UssdPushFeeMethod {
  const UssdPushFeeMethod({
    required this.name,
    required this.status,
    this.fee,
  });

  /// ClickPesa's channel name, e.g. `M-PESA`, `AIRTEL-MONEY`, `MIXX-BY-YAS`.
  final String name;

  /// `AVAILABLE` when the push can be sent on this channel.
  final String status;

  /// Fee in TZS for this channel, or null when ClickPesa omitted it (which it
  /// does for unavailable methods).
  final double? fee;

  bool get isAvailable => status == 'AVAILABLE' && fee != null;
}

/// Authoritative fee quote for a push, as recomputed by our backend.
class UssdPushFeeQuote {
  const UssdPushFeeQuote({
    required this.totalAmount,
    required this.platformFee,
    required this.gatewayFee,
    required this.methods,
  });

  /// The amount that will actually be pushed, computed server-side from the
  /// flash-sale-aware price + shipping + commission + gateway fee. Trust this
  /// over any client-side total — it matches what the payment route charges.
  final double totalAmount;

  final double platformFee;
  final double gatewayFee;
  final List<UssdPushFeeMethod> methods;

  /// Cheapest fee across the channels a buyer can actually pay on, or null when
  /// ClickPesa returned no usable method (e.g. every channel down).
  ///
  /// Used as the figure shown to the buyer because it is what their channel
  /// will really charge; [UssdPushFeeMethod.fee] already includes the MNO cost.
  double? get cheapestAvailableFee {
    double? best;
    for (final m in methods) {
      final f = m.fee;
      if (!m.isAvailable || f == null) continue;
      if (best == null || f < best) best = f;
    }
    return best;
  }

  /// Channels a buyer can currently pay on, for display.
  List<UssdPushFeeMethod> get availableMethods =>
      methods.where((m) => m.isAvailable).toList();
}

class ClickPesaService {
  // ─── Payin (Collection) ───

  /// Render free tier sleeps after ~15 min idle; the first request wakes it and
  /// can take up to ~60s, so escalation retries instead of failing the cold start.
  static const List<Duration> _initAttemptTimeouts = [
    Duration(seconds: 10),
    Duration(seconds: 25),
    Duration(seconds: 60),
  ];

  static Future<Map<String, dynamic>?> initiateMarketplacePayment({
    required double productPrice,
    required String productName,
    required String productId,
    required String sellerId,
    required String sellerName,
    required String email,
    required String phone,
    String? buyerId,
    String? buyerName,
    String deliveryType = 'local',
    String? existingTransactionId,
    String paymentMethod = 'ussd_push',
    double shippingCost = 0,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < _initAttemptTimeouts.length; attempt++) {
      try {
        final url = '${ApiConfig.baseUrl}/api/create-marketplace-payment-link';
        final token = await FirebaseAuth.instance.currentUser?.getIdToken();
        debugPrint('ClickPesa: POST $url (attempt ${attempt + 1})');
        final resp = await http.post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'productPrice': productPrice,
            'productName': productName,
            'productId': productId,
            'sellerId': sellerId,
            'sellerName': sellerName,
            'email': email,
            'phone': phone,
            'buyerId': buyerId ?? '',
            'buyerName': buyerName ?? '',
            'deliveryType': deliveryType,
            'paymentMethod': paymentMethod,
            'shippingCost': shippingCost,
            'existingTransactionId': ?existingTransactionId,
          }),
        ).timeout(_initAttemptTimeouts[attempt]);

        debugPrint('ClickPesa: status ${resp.statusCode} body ${resp.body}');
        if (resp.statusCode != 200) {
          debugPrint('ClickPesa: non-200 response');
          return {'error': resp.body};
        }

        return jsonDecode(resp.body) as Map<String, dynamic>;
      } catch (e) {
        // Network/timeout errors during a wake-up are retried; everything else
        // (auth, bad request) should surface to the caller immediately. The
        // caller renders the exception via context.trError(), which localizes it.
        lastError = e;
        final kind = classifyFirestoreError(e).kind;
        if (kind != FirestoreErrorKind.network) rethrow;
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    throw lastError ?? TimeoutException('Payment init timed out');
  }

  // ─── Fee preview ───

  /// Authoritative fee quote for a USSD push, straight from ClickPesa.
  ///
  /// The local tier table only knows ClickPesa's own fee. ClickPesa bills that
  /// "in addition to the charges of the MNOs", so the table under-quotes every
  /// payment and the buyer's phone is debited more than the app showed. This
  /// call is what makes the checkout figure match the real debit.
  ///
  /// Returns null on any failure (offline, denied, ClickPesa down) so the
  /// caller can fall back to the local table instead of blocking checkout.
  static Future<UssdPushFeeQuote?> previewUssdPushFee({
    required double productPrice,
    required String productId,
    required String phone,
    String? buyerId,
    double shippingCost = 0,
    String paymentMethod = 'ussd_push',
    String? provider,
  }) async {
    try {
      final url = '${ApiConfig.baseUrl}/api/clickpesa/preview-ussd-push';
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      final resp = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'productPrice': productPrice,
              'productId': productId,
              'phone': phone,
              'buyerId': ?buyerId,
              'shippingCost': shippingCost,
              'paymentMethod': paymentMethod,
              'provider': ?provider,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        debugPrint('ClickPesa preview: status ${resp.statusCode}');
        return null;
      }

      final body = jsonDecode(resp.body);
      if (body is! Map<String, dynamic>) return null;
      final rawMethods = body['methods'];
      final methods = <UssdPushFeeMethod>[];
      if (rawMethods is List) {
        for (final m in rawMethods) {
          if (m is! Map) continue;
          final feeRaw = m['fee'];
          methods.add(
            UssdPushFeeMethod(
              name: m['name']?.toString() ?? '',
              status: m['status']?.toString() ?? 'UNKNOWN',
              fee: feeRaw == null ? null : double.tryParse('$feeRaw'),
            ),
          );
        }
      }
      return UssdPushFeeQuote(
        totalAmount: double.tryParse('${body['totalAmount']}') ?? 0,
        platformFee: double.tryParse('${body['platformFee']}') ?? 0,
        gatewayFee: double.tryParse('${body['gatewayFee']}') ?? 0,
        methods: methods,
      );
    } catch (e) {
      debugPrint('ClickPesa preview failed: $e');
      return null;
    }
  }

  // ─── Payout (Withdrawal) ───
  // Seller withdrawals migrated to the Postgres wallet (WalletApiClient /
  // /api/v1/wallet); the legacy /api/payouts/seller/withdraw was retired.

  static Future<Map<String, dynamic>> adminWithdraw({
    required String userId,
    required int amount,
    required String phone,
  }) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    final resp = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/admin/withdraw'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'userId': userId, 'amount': amount, 'phone': phone}),
    );
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode != 200) {
      throw Exception(body['error'] ?? 'Withdrawal failed');
    }
    return body;
  }

  static Future<Map<String, dynamic>?> getFinanceSummary() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final token = await user?.getIdToken();
      final resp = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/finance-summary'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );
      if (resp.statusCode != 200) return null;
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('ClickPesaService getFinanceSummary: $e');
      return null;
    }
  }
}