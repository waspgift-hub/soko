import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'api_config.dart';
import '../utils/network_error.dart';

/// Fee quoted by AzamPay for one payment method on a MNO checkout.
class MnoCheckoutFeeMethod {
  const MnoCheckoutFeeMethod({
    required this.name,
    required this.status,
    this.fee,
  });

  /// AzamPay's channel name, e.g. `AIRTEL`, `MPESA`, `TIGO`, `HALOPESA`.
  final String name;

  /// `AVAILABLE` when the checkout can be sent on this channel.
  final String status;

  /// Fee in TZS for this channel, or null when AzamPay omitted it.
  final double? fee;

  bool get isAvailable => status == 'AVAILABLE' && fee != null;
}

/// Authoritative fee quote for a checkout, as recomputed by our backend.
class MnoCheckoutFeeQuote {
  const MnoCheckoutFeeQuote({
    required this.totalAmount,
    required this.platformFee,
    required this.gatewayFee,
    required this.methods,
  });

  /// The amount that will actually be pushed, computed server-side.
  final double totalAmount;

  final double platformFee;
  final double gatewayFee;
  final List<MnoCheckoutFeeMethod> methods;

  double? get cheapestAvailableFee {
    double? best;
    for (final m in methods) {
      final f = m.fee;
      if (!m.isAvailable || f == null) continue;
      if (best == null || f < best) best = f;
    }
    return best;
  }

  List<MnoCheckoutFeeMethod> get availableMethods =>
      methods.where((m) => m.isAvailable).toList();
}

class AzamPayService {
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
    String paymentMethod = 'mno_checkout',
    double shippingCost = 0,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < _initAttemptTimeouts.length; attempt++) {
      try {
        final url = '${ApiConfig.baseUrl}/api/create-marketplace-payment-link';
        final token = await FirebaseAuth.instance.currentUser?.getIdToken();
        debugPrint('AzamPay: POST $url (attempt ${attempt + 1})');
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
            'existingTransactionId': existingTransactionId,
          }),
        ).timeout(_initAttemptTimeouts[attempt]);

        debugPrint('AzamPay: status ${resp.statusCode} body ${resp.body}');
        if (resp.statusCode != 200) {
          debugPrint('AzamPay: non-200 response');
          return {'error': resp.body};
        }

        return jsonDecode(resp.body) as Map<String, dynamic>;
      } catch (e) {
        lastError = e;
        final kind = classifyFirestoreError(e).kind;
        if (kind != FirestoreErrorKind.network) rethrow;
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    throw lastError ?? TimeoutException('Payment init timed out');
  }

  static Future<MnoCheckoutFeeQuote?> previewMnoCheckoutFee({
    required double productPrice,
    required String productId,
    required String phone,
    String? buyerId,
    double shippingCost = 0,
    String paymentMethod = 'mno_checkout',
    String? provider,
  }) async {
    try {
      final url = '${ApiConfig.baseUrl}/api/azampay/preview-mno-checkout';
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
              'buyerId': buyerId,
              'shippingCost': shippingCost,
              'paymentMethod': paymentMethod,
              'provider': provider,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        debugPrint('AzamPay preview: status ${resp.statusCode}');
        return null;
      }

      final body = jsonDecode(resp.body);
      if (body is! Map<String, dynamic>) return null;
      final rawMethods = body['methods'];
      final methods = <MnoCheckoutFeeMethod>[];
      if (rawMethods is List) {
        for (final m in rawMethods) {
          if (m is! Map) continue;
          final feeRaw = m['fee'];
          methods.add(
            MnoCheckoutFeeMethod(
              name: m['name']?.toString() ?? '',
              status: m['status']?.toString() ?? 'UNKNOWN',
              fee: feeRaw == null ? null : double.tryParse('$feeRaw'),
            ),
          );
        }
      }
      return MnoCheckoutFeeQuote(
        totalAmount: double.tryParse('${body['totalAmount']}') ?? 0,
        platformFee: double.tryParse('${body['platformFee']}') ?? 0,
        gatewayFee: double.tryParse('${body['gatewayFee']}') ?? 0,
        methods: methods,
      );
    } catch (e) {
      debugPrint('AzamPay preview failed: $e');
      return null;
    }
  }

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
      debugPrint('AzamPayService getFinanceSummary: $e');
      return null;
    }
  }
}
