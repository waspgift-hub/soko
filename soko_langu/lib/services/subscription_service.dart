import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';

class SubscriptionPlan {
  final String id;
  final String name;
  final num price;
  final String currency;
  final String billingPeriod;
  final List<String> features;

  SubscriptionPlan({
    required this.id,
    required this.name,
    required this.price,
    this.currency = 'TZS',
    this.billingPeriod = 'month',
    this.features = const [],
  });

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    return SubscriptionPlan(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? json['id']?.toString() ?? '',
      price: json['price'] ?? 0,
      currency: json['currency']?.toString() ?? 'TZS',
      billingPeriod: json['billingPeriod']?.toString() ?? 'month',
      features: (json['features'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }
}

class UserSubscription {
  final String? planId;
  final String status;
  final String? nextBillingDate;
  final String? expiresAt;

  UserSubscription({
    this.planId,
    this.status = 'FREE',
    this.nextBillingDate,
    this.expiresAt,
  });

  factory UserSubscription.fromJson(Map<String, dynamic> json) {
    return UserSubscription(
      planId: json['planId']?.toString() ?? json['plan']?.toString(),
      status: json['status']?.toString() ?? 'FREE',
      nextBillingDate: json['nextBillingDate']?.toString() ?? json['nextBilling']?.toString(),
      expiresAt: json['expiresAt']?.toString() ?? json['expiryDate']?.toString(),
    );
  }
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

  Future<List<SubscriptionPlan>> fetchPlans() async {
    try {
      final res = await http
          .get(Uri.parse(ApiConfig.v1('/subscriptions/plans')), headers: await _headers())
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return const [];
      final body = jsonDecode(res.body);
      final data = body is Map<String, dynamic> ? body['data'] : null;
      if (data is List) {
        return data.whereType<Map<String, dynamic>>().map(SubscriptionPlan.fromJson).toList();
      }
      if (data is Map<String, dynamic> && data['plans'] is List) {
        return (data['plans'] as List).whereType<Map<String, dynamic>>().map(SubscriptionPlan.fromJson).toList();
      }
      return const [];
    } catch (e) {
      debugPrint('[SubscriptionService] fetchPlans failed: $e');
      return const [];
    }
  }

  Future<UserSubscription?> fetchSubscription() async {
    try {
      final res = await http
          .get(Uri.parse(ApiConfig.v1('/subscriptions/subscription')), headers: await _headers())
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      final data = body is Map<String, dynamic> ? body['data'] : null;
      if (data is Map<String, dynamic>) return UserSubscription.fromJson(data);
      return null;
    } catch (e) {
      debugPrint('[SubscriptionService] fetchSubscription failed: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> fetchEntitlements() async {
    try {
      final res = await http
          .get(Uri.parse(ApiConfig.v1('/subscriptions/entitlements')), headers: await _headers())
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      final data = body is Map<String, dynamic> ? body['data'] : null;
      return data is Map<String, dynamic> ? data : null;
    } catch (e) {
      debugPrint('[SubscriptionService] fetchEntitlements failed: $e');
      return null;
    }
  }

  Future<bool> startTrial(String planId) async {
    try {
      final res = await http
          .post(
            Uri.parse(ApiConfig.v1('/subscriptions/trial')),
            headers: await _headers(),
            body: jsonEncode({'planId': planId}),
          )
          .timeout(const Duration(seconds: 12));
      return res.statusCode == 201;
    } catch (e) {
      debugPrint('[SubscriptionService] startTrial failed: $e');
      return false;
    }
  }
}
