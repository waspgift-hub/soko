class ApiConfig {
  static const String baseUrl = 'https://sokolangu-production.up.railway.app';

  /// Master test mode — false = production for all features (fraud, etc.)
  static const bool kIsTestMode = false;

  /// Ads-specific flag — stays true to keep AdMob in test mode
  static const bool kAdsTestMode = true;
}
