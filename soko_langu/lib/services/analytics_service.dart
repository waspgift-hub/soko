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

  CollectionReference get _boostImpressions =>
      _firestore.collection('boost_analytics');

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

  // ── Track Boost Impression ────────────────────────────────────────────

  Future<void> trackBoostImpression(String productId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      String? location;
      if (user != null) {
        final profileDoc = await _firestore
            .collection('users')
            .doc(user.uid)
            .get();
        if (profileDoc.exists) {
          location = profileDoc.data()?['location'] as String?;
        }
      }

      await _boostImpressions
          .doc(productId)
          .collection('impressions')
          .add(
            BoostImpressionRecord(
              id: '',
              productId: productId,
              location: location,
              timestamp: DateTime.now(),
            ).toMap(),
          );
    } catch (e) {
      // Silently fail
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

  // ── Get Boost Stats for Product ──────────────────────────────────────

  Future<MapEntry<int, Map<String, int>>> getBoostStats(
    String productId,
  ) async {
    int total = 0;
    final locations = <String, int>{};
    try {
      final snap = await _boostImpressions
          .doc(productId)
          .collection('impressions')
          .get();
      total = snap.docs.length;
      for (final doc in snap.docs) {
        final loc = doc.data()['location'] as String? ?? 'unknown';
        locations[loc] = (locations[loc] ?? 0) + 1;
      }
    } catch (_) {}
    return MapEntry(total, locations);
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
      final sessions = await _firestore.collection('user_sessions').get();
      final allTime = sessions.docs.length;
      final now = DateTime.now();
      int perSecond = 0, perMinute = 0, perHour = 0;
      int perDay = 0, perMonth = 0, perYear = 0;

      for (final doc in sessions.docs) {
        final ts = (doc.data()['lastActive'] as Timestamp?)?.toDate();
        if (ts == null) continue;
        final diff = now.difference(ts);
        if (diff.inSeconds <= 1) perSecond++;
        if (diff.inMinutes <= 1) perMinute++;
        if (diff.inHours <= 1) perHour++;
        if (diff.inDays <= 1) perDay++;
        if (diff.inDays <= 30) perMonth++;
        if (diff.inDays <= 365) perYear++;
      }

      return AppUsageStats(
        perSecond: perSecond,
        perMinute: perMinute,
        perHour: perHour,
        perDay: perDay,
        perMonth: perMonth,
        perYear: perYear,
        allTime: allTime,
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
        boostImpressions: (result['boostImpressions'] as num?)?.toInt() ?? 0,
        boostLocationBreakdown: parseStringIntMap(result['boostLocationBreakdown'] as Map<String, dynamic>?),
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

  // ── Get App-Wide Analytics (Admin) ────────────────────────────────────

  Future<SellerAnalytics> getAppAnalytics() async {
    int totalProducts = 0;
    int totalProductViews = 0;
    final genderBreakdown = <String, int>{};
    final locationBreakdown = <String, int>{};
    final ageBreakdown = <String, int>{};
    int boostImpressions = 0;
    final boostLocations = <String, int>{};
    final List<TopProduct> topProducts = [];
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthlySales = List.generate(12, (i) {
      final m = (now.month - 1 - (11 - i) + 12) % 12 + 1;
      return DailyMetric(date: DateTime(now.year, m, 1), count: 0);
    });

    try {
      final productsSnap = await _firestore.collection('products').get();
      totalProducts = productsSnap.docs.length;

      final productFutures = <Future<void>>[];
      for (final productDoc in productsSnap.docs) {
        final pid = productDoc.id;
        final pData = productDoc.data();
        totalProductViews += (pData['viewCount'] as num?)?.toInt() ?? 0;

        productFutures.add(() async {
          final results = await Future.wait([
            _productViews
                .doc(pid)
                .collection('views')
                .where('gender', isNotEqualTo: null)
                .get(),
            _productViews
                .doc(pid)
                .collection('views')
                .where('location', isNotEqualTo: null)
                .get(),
            _productViews
                .doc(pid)
                .collection('views')
                .where('age', isNotEqualTo: null)
                .get(),
            _boostImpressions.doc(pid).collection('impressions').get(),
            _productViews.doc(pid).collection('views').count().get(),
          ]);

          final gSnap = results[0] as QuerySnapshot;
          for (final doc in gSnap.docs) {
            final g =
                (doc.data() as Map<String, dynamic>)['gender'] as String? ??
                'unknown';
            genderBreakdown[g] = (genderBreakdown[g] ?? 0) + 1;
          }

          final lSnap = results[1] as QuerySnapshot;
          final prodLocBreakdown = <String, int>{};
          for (final doc in lSnap.docs) {
            final loc =
                (doc.data() as Map<String, dynamic>)['location'] as String? ??
                'unknown';
            locationBreakdown[loc] = (locationBreakdown[loc] ?? 0) + 1;
            prodLocBreakdown[loc] = (prodLocBreakdown[loc] ?? 0) + 1;
          }

          final aSnap = results[2] as QuerySnapshot;
          for (final doc in aSnap.docs) {
            final age =
                (doc.data() as Map<String, dynamic>)['age'] as int? ?? 0;
            final group = _ageGroup(age);
            ageBreakdown[group] = (ageBreakdown[group] ?? 0) + 1;
          }

          final bSnap = results[3] as QuerySnapshot;
          boostImpressions += bSnap.docs.length;
          for (final doc in bSnap.docs) {
            final loc =
                (doc.data() as Map<String, dynamic>)['location'] as String? ??
                'unknown';
            boostLocations[loc] = (boostLocations[loc] ?? 0) + 1;
          }

          final countSnap = results[4] as AggregateQuerySnapshot;
          final viewCount = countSnap.count ?? 0;

          topProducts.add(
            TopProduct(
              productId: pid,
              productName: pData['name'] as String? ?? 'Bidhaa',
              productImage: pData['images'] is List
                  ? (pData['images'] as List).firstOrNull as String?
                  : pData['image'] as String?,
              viewCount: viewCount,
              locationBreakdown: prodLocBreakdown,
            ),
          );
        }());
      }
      await Future.wait(productFutures);
    } catch (_) {}

    int totalOrders = 0;
    int successfulOrders = 0;
    int failedOrders = 0;
    double monthlyEarnings = 0;
    int totalTransactions = 0;
    int successfulTransactions = 0;
    int failedTransactions = 0;

    try {
      final txSnap = await _firestore.collection('transactions').get();
      totalTransactions = txSnap.docs.length;

      for (final doc in txSnap.docs) {
        final data = doc.data();
        final status = data['status'] as String? ?? '';
        final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

        if (status == 'completed' ||
            status == 'delivered' ||
            status == 'delivery_confirmed') {
          successfulOrders++;
          successfulTransactions++;
          if (createdAt != null) {
            if (createdAt.isAfter(monthStart)) {
              monthlyEarnings += (data['totalAmount'] as num?)?.toDouble() ?? 0;
            }
            for (int i = 0; i < monthlySales.length; i++) {
              if (createdAt.month == monthlySales[i].date.month &&
                  createdAt.year == monthlySales[i].date.year) {
                monthlySales[i] = DailyMetric(
                  date: monthlySales[i].date,
                  count: monthlySales[i].count + 1,
                );
                break;
              }
            }
          }
        } else if (status == 'failed' || status == 'refunded') {
          failedOrders++;
          failedTransactions++;
        }
        totalOrders++;
      }
    } catch (_) {}

    double averageRating = 0;
    int totalReviews = 0;
    int positiveReviews = 0;
    int negativeReviews = 0;

    try {
      final reviewSnap = await _firestore.collection('reviews').get();
      totalReviews = reviewSnap.docs.length;
      double totalRating = 0;
      for (final doc in reviewSnap.docs) {
        final rating = (doc.data()['rating'] as num?)?.toDouble() ?? 0;
        totalRating += rating;
        if (rating >= 4) positiveReviews++;
        if (rating <= 2) negativeReviews++;
      }
      averageRating = totalReviews > 0 ? totalRating / totalReviews : 0;
    } catch (_) {}

    topProducts.sort((a, b) => b.viewCount.compareTo(a.viewCount));

    return SellerAnalytics(
      sellerId: 'app',
      totalProducts: totalProducts,
      totalProductViews: totalProductViews,
      genderBreakdown: genderBreakdown,
      locationBreakdown: locationBreakdown,
      ageBreakdown: ageBreakdown,
      boostImpressions: boostImpressions,
      boostLocationBreakdown: boostLocations,
      monthlyEarnings: monthlyEarnings,
      totalOrders: totalOrders,
      successfulOrders: successfulOrders,
      failedOrders: failedOrders,
      totalTransactions: totalTransactions,
      successfulTransactions: successfulTransactions,
      failedTransactions: failedTransactions,
      averageRating: averageRating,
      totalReviews: totalReviews,
      positiveReviews: positiveReviews,
      negativeReviews: negativeReviews,
      topProducts: topProducts.take(10).toList(),
      monthlySales: monthlySales,
      lastUpdated: DateTime.now(),
    );
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
        Uri.parse('${ApiConfig.baseUrl}/api/send-notification'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'title': title, 'body': body, 'sendToAll': true}),
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

  Future<String> generateInsights(SellerAnalytics analytics) async {
    try {
      final groq = GroqService();
      final prompt =
          '''
Hii ni takwimu za muuzaji kwenye Soko Vibe. Chambua na toa ushauri wa kina kwa Kiswahili:
 
Bidhaa: ${analytics.totalProducts}
Matazamio ya bidhaa: ${analytics.totalProductViews}
Wanaume: ${analytics.genderBreakdown['male'] ?? 0}
Wanawake: ${analytics.genderBreakdown['female'] ?? 0}
Eneo linaloangalia sana: ${analytics.topLocation}
Matazamio ya Boost: ${analytics.boostImpressions}
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
      return 'Samahani, siwezi kuchambua takwimu kwa sasa. Tafadhali jaribu tena baadaye.';
    }
  }
}
