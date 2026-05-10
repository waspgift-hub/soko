class AppConstants {
  static const String appName = 'Soko Langu';
  static const String currency = 'TZS';
  static const String country = 'Tanzania';

  static const double boostPrice = 5000;
  static const int boostDurationDays = 30;

  static const double adRevenuePerView = 10;
  static const double sellerAdShare = 0.4;
  static const double platformAdShare = 0.6;

  static const double streamerGiftShare = 0.7;
  static const double platformGiftShare = 0.3;

  static const double payoutFee = 4000;
  static const double payoutFeePlatform = 2000;
  static const double payoutFeeMongike = 2000;

  static const double coinRate = 5;
  static const List<Map<String, int>> coinPackages = [
    {'coins': 100, 'price': 500},
    {'coins': 300, 'price': 1500},
    {'coins': 600, 'price': 2500},
    {'coins': 1000, 'price': 4000},
    {'coins': 2500, 'price': 9000},
    {'coins': 5000, 'price': 15000},
  ];
}
