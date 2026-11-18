import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

/// A purchasable plan, exactly as the server defines it in `plans.js`.
class SubscriptionPlan {
  final String id;
  final String name;
  final num priceTzs;
  final String billingCycle;
  final int aiActionsPerDay;
  final List<String> features;

  const SubscriptionPlan({
    required this.id,
    required this.name,
    required this.priceTzs,
    required this.billingCycle,
    required this.aiActionsPerDay,
    required this.features,
  });

  bool get isFree => priceTzs <= 0;

  /// Monthly equivalent, used to sort and to show "per month" consistently.
  String get priceLabel {
    if (isFree) return 'Free';
    final amount = priceTzs.round().toString().replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+$)'),
          (m) => '${m[1]},',
        );
    return 'TZS $amount';
  }

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    final price = json['priceTzs'] ?? json['price'] ?? 0;
    return SubscriptionPlan(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? json['id']?.toString() ?? '',
      priceTzs: price is num ? price : num.tryParse(price.toString()) ?? 0,
      billingCycle:
          json['billingCycle']?.toString() ?? json['billingPeriod']?.toString() ?? 'month',
      aiActionsPerDay:
          (json['aiActionsPerDay'] as num?)?.toInt() ?? 5,
      features: (json['features'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }
}

/// The user's subscription row: the same document the server bills and expires.
class UserSubscription {
  final String? id;
  final String? planId;
  final String status;
  final DateTime? trialEndsAt;
  final DateTime? currentPeriodStart;
  final DateTime? currentPeriodEnd;
  final bool cancelAtPeriodEnd;
  final String? pendingDowngradePlanId;
  final String? lastPaymentId;

  const UserSubscription({
    this.id,
    this.planId,
    this.status = 'inactive',
    this.trialEndsAt,
    this.currentPeriodStart,
    this.currentPeriodEnd,
    this.cancelAtPeriodEnd = false,
    this.pendingDowngradePlanId,
    this.lastPaymentId,
  });

  bool get isActive => status == 'active';
  bool get isTrialing => status == 'trialing';
  bool get isCancelling => status == 'cancel_pending' || cancelAtPeriodEnd;
  bool get isUsable => isActive || isTrialing;
  DateTime? get effectiveEnd => currentPeriodEnd ?? trialEndsAt;

  factory UserSubscription.fromJson(Map<String, dynamic> json) {
    DateTime? ts(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
      if (v is String) return DateTime.tryParse(v);
      // Firestore Timestamp reaches JSON as {_seconds, _nanoseconds}.
      if (v is Map && v['_seconds'] is num) {
        return DateTime.fromMillisecondsSinceEpoch(
          (v['_seconds'] as num).toInt() * 1000,
        );
      }
      return null;
    }

    return UserSubscription(
      id: json['id']?.toString(),
      planId: json['planId']?.toString() ?? json['plan']?.toString(),
      status: json['status']?.toString() ?? 'inactive',
      trialEndsAt: ts(json['trialEndsAt']),
      currentPeriodStart: ts(json['currentPeriodStart']),
      currentPeriodEnd: ts(json['currentPeriodEnd']),
      cancelAtPeriodEnd: json['cancelAtPeriodEnd'] == true,
      pendingDowngradePlanId: json['pendingDowngradePlanId']?.toString(),
      lastPaymentId: json['lastPaymentId']?.toString(),
    );
  }
}

/// Today's AI allowance. The server increments it transactionally before each
/// AI turn, so this is a display of server state, never a client-side limit.
class AiQuota {
  final int used;
  final int limit;
  final String planId;
  final String dateKey;

  const AiQuota({
    required this.used,
    required this.limit,
    required this.planId,
    required this.dateKey,
  });

  int get remaining => (limit - used).clamp(0, limit);
  double get ratio => limit <= 0 ? 1 : (used / limit).clamp(0, 1).toDouble();
  bool get exhausted => remaining <= 0;

  factory AiQuota.fromJson(Map<String, dynamic> json) {
    return AiQuota(
      used: (json['used'] as num?)?.toInt() ?? 0,
      limit: (json['limit'] as num?)?.toInt() ?? 0,
      planId: json['planId']?.toString() ?? '',
      dateKey: json['dateKey']?.toString() ?? '',
    );
  }
}

/// One row from `billing_payments` — a receipt or a failed attempt.
class SubscriptionInvoice {
  final String id;
  final String? planId;
  final num amount;
  final String currency;
  final String status;
  final String? failureReason;
  final DateTime? createdAt;

  const SubscriptionInvoice({
    required this.id,
    required this.planId,
    required this.amount,
    required this.currency,
    required this.status,
    required this.failureReason,
    required this.createdAt,
  });

  factory SubscriptionInvoice.fromJson(Map<String, dynamic> json) {
    final created = json['createdAt'];
    return SubscriptionInvoice(
      id: json['id']?.toString() ?? '',
      planId: json['planId']?.toString(),
      amount: (json['amount'] as num?) ?? 0,
      currency: json['currency']?.toString() ?? 'TZS',
      status: json['status']?.toString() ?? 'pending',
      failureReason: json['failureReason']?.toString(),
      createdAt: created is String ? DateTime.tryParse(created) : null,
    );
  }
}

/// A rejected subscription call, carrying the server's machine-readable code so
/// the UI can explain exactly what happened (KYC missing, trial used, etc.).
class SubscriptionException implements Exception {
  final String message;
  final String? code;
  final int? statusCode;

  const SubscriptionException(this.message, {this.code, this.statusCode});

  @override
  String toString() => message;
}

class SubscriptionService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<Map<String, String>> _headers() async {
    final user = _auth.currentUser;
    final token = user == null ? null : await user.getIdToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    List<int> okStatuses = const [200, 201],
  }) async {
    final headers = await _headers();
    if (!headers.containsKey('Authorization')) {
      throw const SubscriptionException(
        'Sign in to manage your subscription.',
        code: 'UNAUTHENTICATED',
        statusCode: 401,
      );
    }
    final uri = Uri.parse(ApiConfig.v1(path));
    late http.Response res;
    try {
      switch (method) {
        case 'POST':
          res = await http
              .post(uri, headers: headers, body: jsonEncode(body ?? const {}))
              .timeout(const Duration(seconds: 20));
        case 'PATCH':
          res = await http
              .patch(uri, headers: headers, body: jsonEncode(body ?? const {}))
              .timeout(const Duration(seconds: 20));
        default:
          res = await http
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 15));
      }
    } catch (e) {
      debugPrint('[SubscriptionService] $path failed: $e');
      throw const SubscriptionException(
        'Network error. Check your connection and try again.',
        code: 'NETWORK',
      );
    }

    dynamic decoded;
    try {
      decoded = res.body.isEmpty ? null : jsonDecode(res.body);
    } catch (_) {
      decoded = null;
    }

    if (!okStatuses.contains(res.statusCode)) {
      final code = decoded is Map ? decoded['code']?.toString() : null;
      final message = (decoded is Map ? decoded['message']?.toString() : null) ??
          _messageFor(code) ??
          'Request failed (${res.statusCode})';
      throw SubscriptionException(message, code: code, statusCode: res.statusCode);
    }
    return decoded is Map ? decoded['data'] : decoded;
  }

  String? _messageFor(String? code) {
    switch (code) {
      case 'KYC_NOT_APPROVED':
        return 'Verify your identity (KYC) before starting a paid plan.';
      case 'TRIAL_ALREADY_USED':
        return "You've already used your free trial. Choose a paid plan to continue.";
      case 'INVALID_TRIAL_PLAN':
        return 'This plan has no free trial.';
      case 'INVALID_PLAN':
        return 'That plan is no longer available.';
      case 'INVALID_PHONE':
        return 'Enter a valid mobile money number.';
      case 'SUBSCRIPTION_NOT_CANCELLABLE':
        return 'This subscription cannot be changed right now.';
      case 'SUBSCRIPTION_PERIOD_ENDED':
        return 'This subscription has already ended. Start a new plan.';
      default:
        return null;
    }
  }

  Future<List<SubscriptionPlan>> fetchPlans() async {
    try {
      final data = await _send('GET', '/subscriptions/plans');
      final list = data is List ? data : const [];
      final plans = list
          .whereType<Map>()
          .map((e) => SubscriptionPlan.fromJson(Map<String, dynamic>.from(e)))
          .where((p) => p.id.isNotEmpty)
          .toList();
      plans.sort((a, b) => a.priceTzs.compareTo(b.priceTzs));
      return plans;
    } catch (e) {
      debugPrint('[SubscriptionService] fetchPlans failed: $e');
      return const [];
    }
  }

  Future<UserSubscription?> fetchSubscription() async {
    try {
      final data = await _send('GET', '/subscriptions/subscription');
      if (data is Map) {
        return UserSubscription.fromJson(Map<String, dynamic>.from(data));
      }
      return null;
    } on SubscriptionException catch (e) {
      if (e.statusCode == 401) rethrow;
      debugPrint('[SubscriptionService] fetchSubscription failed: $e');
      return null;
    } catch (e) {
      debugPrint('[SubscriptionService] fetchSubscription failed: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> fetchEntitlements() async {
    try {
      final data = await _send('GET', '/subscriptions/entitlements');
      return data is Map ? Map<String, dynamic>.from(data) : null;
    } catch (e) {
      debugPrint('[SubscriptionService] fetchEntitlements failed: $e');
      return null;
    }
  }

  Future<AiQuota?> fetchAiQuota() async {
    try {
      final data = await _send('GET', '/subscriptions/ai-quota');
      return data is Map
          ? AiQuota.fromJson(Map<String, dynamic>.from(data))
          : null;
    } catch (e) {
      debugPrint('[SubscriptionService] fetchAiQuota failed: $e');
      return null;
    }
  }

  Future<List<SubscriptionInvoice>> fetchInvoices({int limit = 20}) async {
    try {
      final data = await _send('GET', '/subscriptions/invoices?limit=$limit');
      final list = data is List ? data : const [];
      return list
          .whereType<Map>()
          .map((e) => SubscriptionInvoice.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      debugPrint('[SubscriptionService] fetchInvoices failed: $e');
      return const [];
    }
  }

  Future<bool> startTrial(String planId) async {
    try {
      await startTrialOrThrow(planId);
      return true;
    } catch (e) {
      debugPrint('[SubscriptionService] startTrial failed: $e');
      return false;
    }
  }

  /// Same as [startTrial] but surfaces the server reason (KYC missing, trial
  /// already used) so the paywall can explain it instead of failing silently.
  Future<void> startTrialOrThrow(String planId) async {
    await _send('POST', '/subscriptions/trial', body: {'planId': planId});
  }

  /// Starts or renews a paid plan. The amount is never sent: the server prices
  /// the plan from `plans.js` and records a `billing_payments` row.
  Future<String> upgrade({required String planId, required String phone}) async {
    final data = await _send(
      'POST',
      '/subscriptions/upgrade',
      body: {'planId': planId, 'phone': phone},
    );
    if (data is Map && data['orderReference'] != null) {
      return data['orderReference'].toString();
    }
    return '';
  }

  Future<DateTime?> cancel() async {
    final data = await _send('POST', '/subscriptions/cancel');
    if (data is Map && data['effectiveAt'] != null) {
      return DateTime.tryParse(data['effectiveAt'].toString());
    }
    return null;
  }

  Future<void> resume() async {
    await _send('POST', '/subscriptions/resume');
  }

  Future<DateTime?> downgrade(String planId) async {
    final data = await _send(
      'POST',
      '/subscriptions/downgrade',
      body: {'planId': planId},
    );
    if (data is Map && data['effectiveAt'] != null) {
      return DateTime.tryParse(data['effectiveAt'].toString());
    }
    return null;
  }
}
