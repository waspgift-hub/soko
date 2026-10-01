import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../models/analytics_models.dart';
import 'groq_service.dart';
import 'api_config.dart';

class AnalyticsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference get _productViews =>
      _firestore.collection('product_analytics');

  // ── Track Product View ────────────────────────────────────────────────

  Future<void> trackProductView(String productId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      String? gender;
      String? location;
      int? age;

      if (user != null) {
        final profileDoc = await _firestore
            .collection('users')
            .doc(user.uid)
            .get();
        if (profileDoc.exists) {
          final data = profileDoc.data()!;
          gender = data['gender'] as String?;
          location = data['location'] as String?;
          final dob = data['dateOfBirth'] as String?;
          if (dob != null && dob.isNotEmpty) {
            try {
              final birth = DateTime.parse(dob);
              age = DateTime.now().year - birth.year;
            } catch (_) {}
          }
        }

        // Unique view per account: use userId as doc ID, skip if already exists
        final viewsCol = _productViews.doc(productId).collection('views');
        final existing = await viewsCol.doc(user.uid).get();
        if (existing.exists) return;
        await viewsCol
            .doc(user.uid)
            .set(
              ProductViewRecord(
                id: user.uid,
                productId: productId,
                userId: user.uid,
                gender: gender,
                location: location,
                age: age,
                timestamp: DateTime.now(),
              ).toMap(),
            );
      } else {
        // Anonymous view — allow one per session (capped by caller)
        await _productViews
            .doc(productId)
            .collection('views')
            .add(
              ProductViewRecord(
                id: '',
                productId: productId,
                userId: null,
                gender: gender,
                location: location,
                age: age,
                timestamp: DateTime.now(),
              ).toMap(),
            );
      }

      // Increment viewCount on product doc
      await _firestore.collection('products').doc(productId).update({
        'viewCount': FieldValue.increment(1),
      });
    } catch (e) {
      // Silently fail — analytics should never block the UI
    }
  }

  // ── Get Product View Count ────────────────────────────────────────────

  Future<int> getProductViewCount(String productId) async {
    try {
      final snap = await _productViews
          .doc(productId)
          .collection('views')
          .count()
          .get();
      return snap.count ?? 0;
    } catch (_) {
      return 0;
    }
  }

  // ── Get Gender Breakdown for Product ──────────────────────────────────

  Future<Map<String, int>> getGenderBreakdown(String productId) async {
    final result = <String, int>{};
    try {
      final snap = await _productViews
          .doc(productId)
          .collection('views')
          .where('gender', isNotEqualTo: null)
          .get();
      for (final doc in snap.docs) {
        final g = doc.data()['gender'] as String? ?? 'unknown';
        result[g] = (result[g] ?? 0) + 1;
      }
    } catch (_) {}
    return result;
  }

  // ── Get Location Breakdown for Product ────────────────────────────────

  Future<Map<String, int>> getLocationBreakdown(String productId) async {
    final result = <String, int>{};
    try {
      final snap = await _productViews
          .doc(productId)
          .collection('views')
          .where('location', isNotEqualTo: null)
          .get();
      for (final doc in snap.docs) {
        final loc = doc.data()['location'] as String? ?? 'unknown';
        result[loc] = (result[loc] ?? 0) + 1;
      }
    } catch (_) {}
    return result;
  }

  // ── Get Age Breakdown for Product ─────────────────────────────────────

  Future<Map<String, int>> getAgeBreakdown(String productId) async {
    final result = <String, int>{};
    try {
      final snap = await _productViews
          .doc(productId)
          .collection('views')
          .where('age', isNotEqualTo: null)
          .get();
      for (final doc in snap.docs) {
        final age = doc.data()['age'] as int? ?? 0;
        final group = _ageGroup(age);
        result[group] = (result[group] ?? 0) + 1;
      }
    } catch (_) {}
    return result;
  }

  String _ageGroup(int age) {
    if (age < 18) return 'Under 18';
    if (age < 25) return '18-24';
    if (age < 35) return '25-34';
    if (age < 50) return '35-49';
    return '50+';
  }

  // ── Track User Session ────────────────────────────────────────────────

  Future<void> trackUserSession(String uid) async {
    try {
      await _firestore.collection('user_sessions').doc(uid).set({
        'lastActive': FieldValue.serverTimestamp(),
        'uid': uid,
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  // ── Get Active User Counts ────────────────────────────────────────────

  Future<AppUsageStats> getActiveUserCounts() async {
    try {
      final sessions = _firestore.collection('user_sessions');
      final now = DateTime.now();

      // Bounded server-side counts avoid downloading every session document,
      // so dashboard cost stays constant as the user base grows.
      Future<int> countSince(Duration window) async {
        final cutoff = Timestamp.fromDate(now.subtract(window));
        final snap = await sessions
            .where('lastActive', isGreaterThan: cutoff)
            .count()
            .get();
        return snap.count ?? 0;
      }

      final results = await Future.wait<int>([
        countSince(const Duration(seconds: 1)),
        countSince(const Duration(minutes: 1)),
        countSince(const Duration(hours: 1)),
        countSince(const Duration(days: 1)),
        countSince(const Duration(days: 30)),
        countSince(const Duration(days: 365)),
        sessions.count().get().then((snap) => snap.count ?? 0),
      ]);

      return AppUsageStats(
        perSecond: results[0],
        perMinute: results[1],
        perHour: results[2],
        perDay: results[3],
        perMonth: results[4],
        perYear: results[5],
        allTime: results[6],
      );
    } catch (_) {
      return const AppUsageStats();
    }
  }

  // ── Get Full Seller Analytics ─────────────────────────────────────────

  Future<SellerAnalytics> getSellerAnalytics(String sellerId) async {
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) return SellerAnalytics(lastUpdated: DateTime.now());
      final resp = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/api/seller-analytics/$sellerId'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return SellerAnalytics(lastUpdated: DateTime.now());
      final result = jsonDecode(resp.body);
      if (result['success'] != true) return SellerAnalytics(lastUpdated: DateTime.now());

      List<TopProduct> parseTopProducts(List raw) {
        return raw.map((e) => TopProduct(
          productId: e['productId'] ?? '',
          productName: e['productName'] ?? 'Bidhaa',
          productImage: e['productImage'] as String?,
          viewCount: (e['viewCount'] as num?)?.toInt() ?? 0,
          locationBreakdown: (e['locationBreakdown'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, (v as num).toInt())) ?? {},
        )).toList();
      }

      List<DailyMetric> parseMonthlySales(List raw) {
        return raw.map((e) {
          final date = DateTime.tryParse(e['date'] as String? ?? '') ?? DateTime.now();
          return DailyMetric(date: date, count: (e['count'] as num?)?.toInt() ?? 0);
        }).toList();
      }

      Map<String, int> parseStringIntMap(Map<String, dynamic>? map) {
        if (map == null) return {};
        return map.map((k, v) => MapEntry(k, (v as num).toInt()));
      }

      return SellerAnalytics(
        sellerId: result['sellerId'] ?? sellerId,
        totalProducts: (result['totalProducts'] as num?)?.toInt() ?? 0,
        totalProductViews: (result['totalProductViews'] as num?)?.toInt() ?? 0,
        genderBreakdown: parseStringIntMap(result['genderBreakdown'] as Map<String, dynamic>?),
        locationBreakdown: parseStringIntMap(result['locationBreakdown'] as Map<String, dynamic>?),
        ageBreakdown: parseStringIntMap(result['ageBreakdown'] as Map<String, dynamic>?),
        monthlyEarnings: (result['monthlyEarnings'] as num?)?.toDouble() ?? 0,
        totalOrders: (result['totalOrders'] as num?)?.toInt() ?? 0,
        successfulOrders: (result['successfulOrders'] as num?)?.toInt() ?? 0,
        failedOrders: (result['failedOrders'] as num?)?.toInt() ?? 0,
        totalTransactions: (result['totalTransactions'] as num?)?.toInt() ?? 0,
        successfulTransactions: (result['successfulTransactions'] as num?)?.toInt() ?? 0,
        failedTransactions: (result['failedTransactions'] as num?)?.toInt() ?? 0,
        averageRating: (result['averageRating'] as num?)?.toDouble() ?? 0,
        totalReviews: (result['totalReviews'] as num?)?.toInt() ?? 0,
        positiveReviews: (result['positiveReviews'] as num?)?.toInt() ?? 0,
        negativeReviews: (result['negativeReviews'] as num?)?.toInt() ?? 0,
        topProducts: parseTopProducts(result['topProducts'] as List? ?? []),
        monthlySales: parseMonthlySales(result['monthlySales'] as List? ?? []),
        lastUpdated: DateTime.tryParse(result['lastUpdated'] as String? ?? '') ?? DateTime.now(),
      );
    } catch (_) {
      return SellerAnalytics(lastUpdated: DateTime.now());
    }
  }


  // ── Admin: Load App-Wide Analytics ────────────────────────────────────

  Future<AnalyticsData> loadAnalytics() async {
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) return AnalyticsData();
      final resp = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/api/admin/analytics'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return AnalyticsData();
      final result = jsonDecode(resp.body);
      if (result['success'] != true) return AnalyticsData();

      List<DailyMetric> parseMetrics(String key) {
        final list = result[key] as List? ?? [];
        return list.map((e) {
          final date = DateTime.tryParse(e['date'] as String? ?? '') ?? DateTime.now();
          return DailyMetric(date: date, count: e['count'] ?? 0);
        }).toList();
      }

      Map<String, int> parseStringIntMap(String key) {
        final map = result[key] as Map<String, dynamic>? ?? {};
        return map.map((k, v) => MapEntry(k, (v as num).toInt()));
      }

      final ac = result['activeUserCounts'] as Map<String, dynamic>? ?? {};

      return AnalyticsData(
        totalUsers: (result['totalUsers'] as num?)?.toInt() ?? 0,
        newUsersToday: (result['newUsersToday'] as num?)?.toInt() ?? 0,
        newUsersThisMonth: (result['newUsersThisMonth'] as num?)?.toInt() ?? 0,
        totalProducts: (result['totalProducts'] as num?)?.toInt() ?? 0,
        activeProducts: (result['activeProducts'] as num?)?.toInt() ?? 0,
        inactiveProducts: (result['inactiveProducts'] as num?)?.toInt() ?? 0,
        totalRevenue: (result['totalRevenue'] as num?)?.toDouble() ?? 0,
        revenueToday: (result['revenueToday'] as num?)?.toDouble() ?? 0,
        revenueThisMonth: (result['revenueThisMonth'] as num?)?.toDouble() ?? 0,
        productsByCategory: parseStringIntMap('productsByCategory'),
        revenueOverTime: parseMetrics('revenueOverTime'),
        userGrowth: parseMetrics('userGrowth'),
        locationDistribution: parseStringIntMap('locationDistribution'),
        ageDistribution: parseStringIntMap('ageDistribution'),
        activeUserCounts: AppUsageStats(
          perSecond: (ac['perSecond'] as num?)?.toInt() ?? 0,
          perMinute: (ac['perMinute'] as num?)?.toInt() ?? 0,
          perHour: (ac['perHour'] as num?)?.toInt() ?? 0,
          perDay: (ac['perDay'] as num?)?.toInt() ?? 0,
          perMonth: (ac['perMonth'] as num?)?.toInt() ?? 0,
          perYear: (ac['perYear'] as num?)?.toInt() ?? 0,
          allTime: (ac['allTime'] as num?)?.toInt() ?? 0,
        ),
      );
    } catch (_) {
      return AnalyticsData();
    }
  }

  // ── Admin: Send Push Notification to All Users ─────────────────────────

  Future<void> sendPushToAll(String title, String body) async {
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) return;
      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/notifications/broadcast'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'title': title, 'body': body}),
      );
    } catch (_) {}
  }

  // ── Admin: Maintenance Mode ────────────────────────────────────────────

  Future<bool> getMaintenanceMode() async {
    try {
      final doc = await _firestore
          .collection('app_settings')
          .doc('maintenance')
          .get();
      return doc.data()?['enabled'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> toggleMaintenanceMode(bool enabled, {String? message}) async {
    try {
      await _firestore.collection('app_settings').doc('maintenance').set({
        'enabled': enabled,
        'message':
            message ??
            (enabled
                ? 'App iko kwenye matengenezo. Tafadhali rudi baadaye.'
                : ''),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  // ── AI-Powered Insights ───────────────────────────────────────────────

  /// Builds an advisory prompt from the seller's real analytics data.
  /// Swahili by default; English when the user has set the app to English.
  Future<String> generateInsights(SellerAnalytics analytics, {String locale = 'sw'}) async {
    final isEn = locale == 'en';
    try {
      final groq = GroqService();
      final prompt = isEn
          ? '''
These are real analytics for a seller on Soko Vibe. Analyze and give detailed advice in English:

Products: ${analytics.totalProducts}
Product views: ${analytics.totalProductViews}
Male viewers: ${analytics.genderBreakdown['male'] ?? 0}
Female viewers: ${analytics.genderBreakdown['female'] ?? 0}
Top viewing location: ${analytics.topLocation}
Top viewing age group: ${analytics.topAgeGroup}
Earnings this month: TSh ${analytics.monthlyEarnings.toStringAsFixed(0)}
Total orders: ${analytics.totalOrders}
Successful orders: ${analytics.successfulOrders}
Failed orders: ${analytics.failedOrders}
Success rate: ${analytics.orderSuccessRate.toStringAsFixed(1)}%
Average rating: ${analytics.averageRating.toStringAsFixed(1)}/5
Positive reviews: ${analytics.positiveReviews}
Negative reviews: ${analytics.negativeReviews}

Also factor in the wider economy and world events (e.g. inflation, shopping seasons, holidays, changes in Tanzanian business law) and relate them to the seller's numbers.

Provide:
1. SUMMARY — overall business health
2. ROOT CAUSE — what is causing challenges (failed orders, low rating, etc.)
3. RECOMMENDATIONS — what the seller should do to improve
4. NEW CUSTOMERS — how to get more buyers on Soko Vibe
5. VALUE — the benefit of using Soko Vibe
6. STRATEGIC ADVICE — ways to increase sales and customers
7. EXTERNAL MARKET OUTLOOK — how outside events affect the business

Answer in simple English like a business adviser. Give actionable advice.
'''
          : '''
Hii ni takwimu za muuzaji kwenye Soko Vibe. Chambua na toa ushauri wa kina kwa Kiswahili:

Bidhaa: ${analytics.totalProducts}
Matazamio ya bidhaa: ${analytics.totalProductViews}
Wanaume: ${analytics.genderBreakdown['male'] ?? 0}
Wanawake: ${analytics.genderBreakdown['female'] ?? 0}
Eneo linaloangalia sana: ${analytics.topLocation}
Rika linaloangalia sana: ${analytics.topAgeGroup}
Mapato mwezi huu: TSh ${analytics.monthlyEarnings.toStringAsFixed(0)}
Order zote: ${analytics.totalOrders}
Order zilizofanikiwa: ${analytics.successfulOrders}
Order zilizofeli: ${analytics.failedOrders}
Asilimia ya mafanikio: ${analytics.orderSuccessRate.toStringAsFixed(1)}%
Wastani wa rating: ${analytics.averageRating.toStringAsFixed(1)}/5
Maoni mazuri: ${analytics.positiveReviews}
Maoni mabaya: ${analytics.negativeReviews}

Pia, zingatia hali ya uchumi na matukio makubwa duniani (mfano: mfumuko wa bei, misimu ya ununuzi, sikukuu, mabadiliko ya sheria za biashara Tanzania) — tumia maarifa yako kuhusisha haya na takwimu za muuzaji.

Tafadhali toa:
1. MUHTASARI — Hali ya biashara kwa ujumla
2. CHANZO CHA TATIZO — Nini hasa kinasababisha changamoto (kama order zinashindikana, rating ni chini, n.k.)
3. MAPENDEKEZO — Anafaa kufanya nini kuboresha?
4. WATEJA WAPYA — Anapataje wateja wengi zaidi kwenye Soko Vibe?
5. THAMANI — Anapata faida gani kwa kutumia Soko Vibe?
6. USHAURI WA KIMKAKATI — Njia za kuongeza mauzo na wateja
7. MATAZIO YA SOKO LA NJE — Matukio ya nje yanavyoathiri biashara yake

Jibu kwa Kiswahili, lugha rahisi, kama mshauri wa biashara. Toa ushauri unaotekelezeka.
''';

      return await groq.sendMessage(prompt);
    } catch (e) {
      return isEn
          ? 'Sorry, I cannot analyze the statistics right now. Please try again later.'
          : 'Samahani, siwezi kuchambua takwimu kwa sasa. Tafadhali jaribu tena baadaye.';
    }
  }
}
