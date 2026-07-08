class AnalyticsData {
  final int totalUsers;
  final int newUsersToday;
  final int newUsersThisMonth;
  final int totalProducts;
  final int activeProducts;
  final int inactiveProducts;
  final double totalRevenue;
  final double revenueToday;
  final double revenueThisMonth;
  final Map<String, int> productsByCategory;
  final List<DailyMetric> revenueOverTime;
  final List<DailyMetric> userGrowth;

  AnalyticsData({
    this.totalUsers = 0,
    this.newUsersToday = 0,
    this.newUsersThisMonth = 0,
    this.totalProducts = 0,
    this.activeProducts = 0,
    this.inactiveProducts = 0,
    this.totalRevenue = 0,
    this.revenueToday = 0,
    this.revenueThisMonth = 0,
    this.productsByCategory = const {},
    this.revenueOverTime = const [],
    this.userGrowth = const [],
  });
}

class DailyMetric {
  final DateTime date;
  final num count;
  DailyMetric({required this.date, required this.count});
}

class SellerAnalytics {
  final String sellerId;
  final int totalProducts;
  final int totalProductViews;
  final Map<String, int> genderBreakdown;
  final Map<String, int> locationBreakdown;
  final Map<String, int> ageBreakdown;
  final int boostImpressions;
  final Map<String, int> boostLocationBreakdown;
  final double monthlyEarnings;
  final int totalOrders;
  final int successfulOrders;
  final int failedOrders;
  final int totalTransactions;
  final int successfulTransactions;
  final int failedTransactions;
  final double averageRating;
  final int totalReviews;
  final int positiveReviews;
  final int negativeReviews;
  final DateTime lastUpdated;

  SellerAnalytics({
    this.sellerId = '',
    this.totalProducts = 0,
    this.totalProductViews = 0,
    this.genderBreakdown = const {},
    this.locationBreakdown = const {},
    this.ageBreakdown = const {},
    this.boostImpressions = 0,
    this.boostLocationBreakdown = const {},
    this.monthlyEarnings = 0,
    this.totalOrders = 0,
    this.successfulOrders = 0,
    this.failedOrders = 0,
    this.totalTransactions = 0,
    this.successfulTransactions = 0,
    this.failedTransactions = 0,
    this.averageRating = 0,
    this.totalReviews = 0,
    this.positiveReviews = 0,
    this.negativeReviews = 0,
    required this.lastUpdated,
  });

  String get topLocation {
    if (locationBreakdown.isEmpty) return 'Hakuna';
    return locationBreakdown.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;
  }

  String get topAgeGroup {
    if (ageBreakdown.isEmpty) return 'Hakuna';
    return ageBreakdown.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;
  }

  double get orderSuccessRate {
    if (totalOrders == 0) return 0;
    return (successfulOrders / totalOrders) * 100;
  }
}

class ProductViewRecord {
  final String id;
  final String productId;
  final String? userId;
  final String? gender;
  final String? location;
  final int? age;
  final DateTime timestamp;

  ProductViewRecord({
    required this.id,
    required this.productId,
    this.userId,
    this.gender,
    this.location,
    this.age,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'productId': productId,
        'userId': userId,
        'gender': gender,
        'location': location,
        'age': age,
        'timestamp': timestamp,
      };
}

class BoostImpressionRecord {
  final String id;
  final String productId;
  final String? location;
  final DateTime timestamp;

  BoostImpressionRecord({
    required this.id,
    required this.productId,
    this.location,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'productId': productId,
        'location': location,
        'timestamp': timestamp,
      };
}
