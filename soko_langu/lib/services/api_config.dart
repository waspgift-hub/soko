class ApiConfig {
  static const String baseUrl = 'https://soko-langu-server-production.up.railway.app';

  /// Master test mode — false = production for all features (fraud, etc.)
  static const bool kIsTestMode = false;

  /// Ads-specific flag — true = test ads, false = production AdMob
  static const bool kAdsTestMode = true;
}
