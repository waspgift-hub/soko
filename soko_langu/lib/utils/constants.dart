class AppConstants {
  static const String appName = 'Soko Vibe';
  static const String currency = 'TZS';
  static const String country = 'Tanzania';

  static const List<Map<String, dynamic>> boostTiers = [
    {'name': 'Bronze', 'price': 1500, 'days': 3},
    {'name': 'Silver', 'price': 3000, 'days': 7},
    {'name': 'Gold', 'price': 10000, 'days': 30},
  ];

  static const double adRevenuePerView = 10;
  static const double sellerAdShare = 0.0;
  static const double platformAdShare = 1.0;

  static const double payoutFee = 4000;
  static const double payoutFeePlatform = 2000;
}
