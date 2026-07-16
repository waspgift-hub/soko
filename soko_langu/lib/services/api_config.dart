class ApiConfig {
  static const String baseUrl = 'https://soko-langu-server.onrender.com';

  /// Master test mode — false = production for all features (fraud, etc.)
  static const bool kIsTestMode = false;

  /// Ads-specific flag — false = production AdMob, true = test ads (dev only)
  static const bool kAdsTestMode = true;
}
