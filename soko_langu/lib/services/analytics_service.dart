import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';

class DailyMetric {
  final DateTime date;
  final int count;
  DailyMetric({required this.date, required this.count});
}

class AnalyticsData {
  final int totalUsers;
  final int newUsersToday;
  final int newUsersThisWeek;
  final int newUsersThisMonth;
  final List<DailyMetric> userGrowth;
  final int totalProducts;
  final int activeProducts;
  final int inactiveProducts;
  final Map<String, int> productsByCategory;
  final int totalOrders;
  final double totalRevenue;
  final double revenueToday;
  final double revenueThisMonth;
  final List<DailyMetric> revenueOverTime;
  final int totalReports;

  AnalyticsData({
    this.totalUsers = 0,
    this.newUsersToday = 0,
    this.newUsersThisWeek = 0,
    this.newUsersThisMonth = 0,
    this.userGrowth = const [],
    this.totalProducts = 0,
    this.activeProducts = 0,
    this.inactiveProducts = 0,
    this.productsByCategory = const {},
    this.totalOrders = 0,
    this.totalRevenue = 0,
    this.revenueToday = 0,
    this.revenueThisMonth = 0,
    this.revenueOverTime = const [],
    this.totalReports = 0,
  });
}

class AnalyticsService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<List<String>> _collectFcmTokens() async {
    final snap = await _db.collection('users').get();
    return snap.docs
        .map((d) => d.data()['fcmToken'] as String? ?? '')
        .where((t) => t.isNotEmpty)
        .toList();
  }

  Future<Map<String, String>> _adminHeaders() async {
    final token = await _auth.currentUser?.getIdToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<AnalyticsData> loadAnalytics() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = todayStart.subtract(const Duration(days: 7));
    final monthStart = DateTime(now.year, now.month, 1);

    final usersSnap = await _db.collection('users').get();
    final allUsers = usersSnap.docs;
    final newToday = allUsers.where((d) {
      final ts = d.data()['createdAt'] as Timestamp?;
      return ts != null && ts.toDate().isAfter(todayStart);
    }).length;
    final newThisWeek = allUsers.where((d) {
      final ts = d.data()['createdAt'] as Timestamp?;
      return ts != null && ts.toDate().isAfter(weekStart);
    }).length;
    final newThisMonth = allUsers.where((d) {
      final ts = d.data()['createdAt'] as Timestamp?;
      return ts != null && ts.toDate().isAfter(monthStart);
    }).length;

    final userGrowth = <DailyMetric>[];
    for (int i = 6; i >= 0; i--) {
      final day = todayStart.subtract(Duration(days: i));
      final nextDay = day.add(const Duration(days: 1));
      final cnt = allUsers.where((d) {
        final ts = d.data()['createdAt'] as Timestamp?;
        if (ts == null) return false;
        final date = ts.toDate();
        return date.isAfter(day) && date.isBefore(nextDay);
      }).length;
      userGrowth.add(DailyMetric(date: day, count: cnt));
    }

    final productsSnap = await _db.collection('products').get();
    final allProducts = productsSnap.docs;
    final activeProducts =
        allProducts.where((d) => d.data()['isActive'] != false).length;
    final inactiveProducts = allProducts.length - activeProducts;

    final catMap = <String, int>{};
    for (final d in allProducts) {
      final cat = d.data()['category'] as String? ?? 'Uncategorized';
      catMap[cat] = (catMap[cat] ?? 0) + 1;
    }

    // Revenue from completed transactions (real payment flow)
    final txSnap = await _db
        .collection('transactions')
        .where('status', whereIn: ['completed', 'delivered'])
        .get();
    final allTx = txSnap.docs;
    double totalRev = 0, todayRev = 0, monthRev = 0;
    for (final d in allTx) {
      final data = d.data();
      final amt = (data['totalAmount'] ?? data['productPrice'] ?? 0).toDouble();
      totalRev += amt;
      final ts = data['createdAt'] as Timestamp?;
      if (ts != null) {
        final date = ts.toDate();
        if (date.isAfter(todayStart)) todayRev += amt;
        if (date.isAfter(monthStart)) monthRev += amt;
      }
    }

    final revenueDays = <DailyMetric>[];
    for (int i = 6; i >= 0; i--) {
      final day = todayStart.subtract(Duration(days: i));
      final nextDay = day.add(const Duration(days: 1));
      double dayRev = 0;
      for (final d in allTx) {
        final data = d.data();
        final ts = data['createdAt'] as Timestamp?;
        if (ts == null) continue;
        final date = ts.toDate();
        if (date.isAfter(day) && date.isBefore(nextDay)) {
          dayRev += (data['totalAmount'] ?? data['productPrice'] ?? 0).toDouble();
        }
      }
      revenueDays.add(DailyMetric(date: day, count: dayRev.round()));
    }

    final reportsSnap = await _db.collection('reports').count().get();
    final totalReports = reportsSnap.count ?? 0;

    return AnalyticsData(
      totalUsers: allUsers.length,
      newUsersToday: newToday,
      newUsersThisWeek: newThisWeek,
      newUsersThisMonth: newThisMonth,
      userGrowth: userGrowth,
      totalProducts: allProducts.length,
      activeProducts: activeProducts,
      inactiveProducts: inactiveProducts,
      productsByCategory: catMap,
      totalOrders: allTx.length,
      totalRevenue: totalRev,
      revenueToday: todayRev,
      revenueThisMonth: monthRev,
      revenueOverTime: revenueDays,
      totalReports: totalReports,
    );
  }

  Future<void> sendPushToAll(String title, String body) async {
    final tokens = await _collectFcmTokens();
    debugPrint('sendPushToAll: ${tokens.length} tokens found');
    if (tokens.isEmpty) return;

    final headers = await _adminHeaders();
    for (int i = 0; i < tokens.length; i += 500) {
      final batch = tokens.skip(i).take(500).toList();
      try {
        await _db.collection('admin_notifications').add({
          'title': title,
          'body': body,
          'target': 'all',
          'sentAt': FieldValue.serverTimestamp(),
          'recipientCount': batch.length,
        });
        await http
            .post(
              Uri.parse('${ApiConfig.baseUrl}/api/send-bulk-notification'),
              headers: headers,
              body: jsonEncode({
                'title': title,
                'body': body,
                'tokens': batch,
                'target': 'all',
                'data': {'type': 'general'},
              }),
            )
            .timeout(const Duration(seconds: 30));
      } catch (e) {
        debugPrint('sendPushToAll batch: $e');
      }
    }
  }

  Future<void> sendPushToTier(String title, String body, String tier) async {
    final tokens = await _collectFcmTokens();
    debugPrint('sendPushToTier($tier): ${tokens.length} tokens');
    if (tokens.isEmpty) return;

    final headers = await _adminHeaders();
    try {
      await _db.collection('admin_notifications').add({
        'title': title,
        'body': body,
        'target': tier,
        'sentAt': FieldValue.serverTimestamp(),
        'recipientCount': tokens.length,
      });
      await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/send-bulk-notification'),
            headers: headers,
            body: jsonEncode({
              'title': title,
              'body': body,
              'tokens': tokens,
              'target': tier,
              'data': {'type': 'general'},
            }),
          )
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      debugPrint('sendPushToTier: $e');
    }
  }

  Future<void> toggleMaintenanceMode(bool enabled) async {
    await _db.collection('app_settings').doc('maintenance').set({
      'enabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': _auth.currentUser?.uid ?? 'unknown',
    });
  }

  Future<bool> getMaintenanceMode() async {
    final doc = await _db.collection('app_settings').doc('maintenance').get();
    return doc.data()?['enabled'] == true;
  }
}
