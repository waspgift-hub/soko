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

  // ── Get Full Seller Analytics ─────────────────────────────────────────

  Future<SellerAnalytics> getSellerAnalytics(String sellerId) async {
    int totalProducts = 0;
    int totalProductViews = 0;
    final genderBreakdown = <String, int>{};
    final locationBreakdown = <String, int>{};
    final ageBreakdown = <String, int>{};
    int boostImpressions = 0;
    final boostLocations = <String, int>{};

    try {
      // Get all products for this seller
      final productsSnap = await _firestore
          .collection('products')
          .where('sellerId', isEqualTo: sellerId)
          .get();
      totalProducts = productsSnap.docs.length;

      // Batch all per-product subcollection queries in parallel
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
          ]);

          final gSnap = results[0] as QuerySnapshot;
          for (final doc in gSnap.docs) {
            final g =
                (doc.data() as Map<String, dynamic>)['gender'] as String? ??
                'unknown';
            genderBreakdown[g] = (genderBreakdown[g] ?? 0) + 1;
          }

          final lSnap = results[1] as QuerySnapshot;
          for (final doc in lSnap.docs) {
            final loc =
                (doc.data() as Map<String, dynamic>)['location'] as String? ??
                'unknown';
            locationBreakdown[loc] = (locationBreakdown[loc] ?? 0) + 1;
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
        }());
      }
      await Future.wait(productFutures);
    } catch (_) {}

    // ── Order & Earnings Stats ──────────────────────────────────────────

    int totalOrders = 0;
    int successfulOrders = 0;
    int failedOrders = 0;
    double monthlyEarnings = 0;
    int totalTransactions = 0;
    int successfulTransactions = 0;
    int failedTransactions = 0;

    try {
      final txSnap = await _firestore
          .collection('transactions')
          .where('sellerId', isEqualTo: sellerId)
          .get();
      totalTransactions = txSnap.docs.length;

      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1);

      for (final doc in txSnap.docs) {
        final data = doc.data();
        final status = data['status'] as String? ?? '';
        final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

        if (status == 'completed' ||
            status == 'delivered' ||
            status == 'delivery_confirmed') {
          successfulOrders++;
          successfulTransactions++;
          if (createdAt != null && createdAt.isAfter(monthStart)) {
            monthlyEarnings += (data['totalAmount'] as num?)?.toDouble() ?? 0;
          }
        } else if (status == 'failed' || status == 'refunded') {
          failedOrders++;
          failedTransactions++;
        }
        totalOrders++;
      }
    } catch (_) {}

    // ── Review Stats ────────────────────────────────────────────────────

    double averageRating = 0;
    int totalReviews = 0;
    int positiveReviews = 0;
    int negativeReviews = 0;

    try {
      final reviewSnap = await _firestore
          .collection('reviews')
          .where('sellerId', isEqualTo: sellerId)
          .get();
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

    return SellerAnalytics(
      sellerId: sellerId,
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
      lastUpdated: DateTime.now(),
    );
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
          ]);

          final gSnap = results[0] as QuerySnapshot;
          for (final doc in gSnap.docs) {
            final g =
                (doc.data() as Map<String, dynamic>)['gender'] as String? ??
                'unknown';
            genderBreakdown[g] = (genderBreakdown[g] ?? 0) + 1;
          }

          final lSnap = results[1] as QuerySnapshot;
          for (final doc in lSnap.docs) {
            final loc =
                (doc.data() as Map<String, dynamic>)['location'] as String? ??
                'unknown';
            locationBreakdown[loc] = (locationBreakdown[loc] ?? 0) + 1;
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
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1);

      for (final doc in txSnap.docs) {
        final data = doc.data();
        final status = data['status'] as String? ?? '';
        final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

        if (status == 'completed' ||
            status == 'delivered' ||
            status == 'delivery_confirmed') {
          successfulOrders++;
          successfulTransactions++;
          if (createdAt != null && createdAt.isAfter(monthStart)) {
            monthlyEarnings += (data['totalAmount'] as num?)?.toDouble() ?? 0;
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
      lastUpdated: DateTime.now(),
    );
  }

  // ── Admin: Load App-Wide Analytics ────────────────────────────────────

  Future<AnalyticsData> loadAnalytics() async {
    int totalUsers = 0;
    int newUsersToday = 0;
    int newUsersThisMonth = 0;
    int totalProducts = 0;
    int activeProducts = 0;
    int inactiveProducts = 0;
    double totalRevenue = 0;
    double revenueToday = 0;
    double revenueThisMonth = 0;
    final productsByCategory = <String, int>{};
    final revenueOverTime = <DailyMetric>[];
    final userGrowth = <DailyMetric>[];
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final monthStart = DateTime(now.year, now.month, 1);
    try {
      // Users
      final usersSnap = await _firestore.collection('users').get();
      totalUsers = usersSnap.docs.length;
      for (final doc in usersSnap.docs) {
        final data = doc.data();
        final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
        if (createdAt != null) {
          if (createdAt.isAfter(todayStart)) newUsersToday++;
          if (createdAt.isAfter(monthStart)) newUsersThisMonth++;
        }
      }

      // Products
      final productsSnap = await _firestore.collection('products').get();
      totalProducts = productsSnap.docs.length;
      for (final doc in productsSnap.docs) {
        final data = doc.data();
        if (data['isActive'] != false) {
          activeProducts++;
        } else {
          inactiveProducts++;
        }
        final cat = data['category'] as String? ?? 'Other';
        productsByCategory[cat] = (productsByCategory[cat] ?? 0) + 1;
      }

      // Revenue (last 7 days)
      final txSnap = await _firestore.collection('transactions').get();
      for (final doc in txSnap.docs) {
        final data = doc.data();
        final status = data['status'] as String? ?? '';
        final amount = (data['totalAmount'] as num?)?.toDouble() ?? 0;
        final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
        if (status == 'completed' ||
            status == 'delivered' ||
            status == 'delivery_confirmed') {
          totalRevenue += amount;
          if (createdAt != null) {
            if (createdAt.isAfter(todayStart)) revenueToday += amount;
            if (createdAt.isAfter(monthStart)) revenueThisMonth += amount;
          }
        }
      }

      // Build last-7-days revenue & user growth
      for (int i = 6; i >= 0; i--) {
        final day = DateTime(now.year, now.month, now.day - i);
        final nextDay = day.add(const Duration(days: 1));
        double dayRev = 0;
        int dayUsers = 0;
        for (final doc in txSnap.docs) {
          final data = doc.data();
          final status = data['status'] as String? ?? '';
          final amount = (data['totalAmount'] as num?)?.toDouble() ?? 0;
          final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
          if (createdAt != null &&
              createdAt.isAfter(day) &&
              createdAt.isBefore(nextDay)) {
            if (status == 'completed' ||
                status == 'delivered' ||
                status == 'delivery_confirmed') {
              dayRev += amount;
            }
          }
        }
        revenueOverTime.add(DailyMetric(date: day, count: dayRev.toInt()));
        for (final doc in usersSnap.docs) {
          final data = doc.data();
          final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
          if (createdAt != null &&
              createdAt.isAfter(day) &&
              createdAt.isBefore(nextDay)) {
            dayUsers++;
          }
        }
        userGrowth.add(DailyMetric(date: day, count: dayUsers));
      }
    } catch (_) {}

    return AnalyticsData(
      totalUsers: totalUsers,
      newUsersToday: newUsersToday,
      newUsersThisMonth: newUsersThisMonth,
      totalProducts: totalProducts,
      activeProducts: activeProducts,
      inactiveProducts: inactiveProducts,
      totalRevenue: totalRevenue,
      revenueToday: revenueToday,
      revenueThisMonth: revenueThisMonth,
      productsByCategory: productsByCategory,
      revenueOverTime: revenueOverTime,
      userGrowth: userGrowth,
    );
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
