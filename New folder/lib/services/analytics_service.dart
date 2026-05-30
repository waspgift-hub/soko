import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AnalyticsService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<Map<String, dynamic>> getDashboardStats() async {
    final user = _auth.currentUser;
    if (user == null) return {};

    final now = DateTime.now();
    final todayStart = Timestamp.fromDate(DateTime(now.year, now.month, now.day));
    final weekStart = Timestamp.fromDate(now.subtract(const Duration(days: 7)));
    final monthStart = Timestamp.fromDate(DateTime(now.year, now.month, 1));

    final ordersSnap = await _db
        .collection('orders')
        .where('sellerId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'delivered')
        .get();

    final productsSnap = await _db
        .collection('products')
        .where('sellerId', isEqualTo: user.uid)
        .where('isActive', isEqualTo: true)
        .count()
        .get();

    final todayOrders = ordersSnap.docs.where((d) {
      final createdAt = d.data()['createdAt'] as Timestamp?;
      return createdAt != null && createdAt.toDate().isAfter(todayStart.toDate());
    }).length;

    final weekOrders = ordersSnap.docs.where((d) {
      final createdAt = d.data()['createdAt'] as Timestamp?;
      return createdAt != null && createdAt.toDate().isAfter(weekStart.toDate());
    }).length;

    final monthOrders = ordersSnap.docs.where((d) {
      final createdAt = d.data()['createdAt'] as Timestamp?;
      return createdAt != null && createdAt.toDate().isAfter(monthStart.toDate());
    }).length;

    double totalRevenue = 0;
    double todayRevenue = 0;
    double weekRevenue = 0;
    double monthRevenue = 0;

    for (final order in ordersSnap.docs) {
      final amount = (order.data()['totalAmount'] ?? 0).toDouble();
      totalRevenue += amount;
      final createdAt = order.data()['createdAt'] as Timestamp?;
      if (createdAt != null) {
        if (createdAt.toDate().isAfter(todayStart.toDate())) todayRevenue += amount;
        if (createdAt.toDate().isAfter(weekStart.toDate())) weekRevenue += amount;
        if (createdAt.toDate().isAfter(monthStart.toDate())) monthRevenue += amount;
      }
    }

    final viewsSnap = await _db
        .collection('products')
        .where('sellerId', isEqualTo: user.uid)
        .get();

    int totalViews = 0;
    for (final doc in viewsSnap.docs) {
      totalViews += (doc.data()['viewCount'] as num?)?.toInt() ?? 0;
    }

    return {
      'totalOrders': ordersSnap.docs.length,
      'todayOrders': todayOrders,
      'weekOrders': weekOrders,
      'monthOrders': monthOrders,
      'totalRevenue': totalRevenue,
      'todayRevenue': todayRevenue,
      'weekRevenue': weekRevenue,
      'monthRevenue': monthRevenue,
      'totalProducts': productsSnap.count ?? 0,
      'totalViews': totalViews,
    };
  }

  Future<List<Map<String, dynamic>>> getTopProducts() async {
    final user = _auth.currentUser;
    if (user == null) return [];

    final snap = await _db
        .collection('products')
        .where('sellerId', isEqualTo: user.uid)
        .where('isActive', isEqualTo: true)
        .orderBy('soldCount', descending: true)
        .limit(10)
        .get();

    return snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
  }

  Future<List<Map<String, dynamic>>> getRevenueByDay(int days) async {
    final user = _auth.currentUser;
    if (user == null) return [];

    final startDate = DateTime.now().subtract(Duration(days: days));

    final snap = await _db
        .collection('orders')
        .where('sellerId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'delivered')
        .get();

    final dailyRevenue = <String, double>{};
    for (final doc in snap.docs) {
      final createdAt = doc.data()['createdAt'] as Timestamp?;
      if (createdAt != null && createdAt.toDate().isAfter(startDate)) {
        final dateKey = '${createdAt.toDate().year}-${createdAt.toDate().month}-${createdAt.toDate().day}';
        dailyRevenue[dateKey] = (dailyRevenue[dateKey] ?? 0) + (doc.data()['totalAmount'] ?? 0).toDouble();
      }
    }

    return dailyRevenue.entries
        .map((e) => {'date': e.key, 'revenue': e.value})
        .toList()
      ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
  }
}
