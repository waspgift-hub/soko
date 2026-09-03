class ApiConfig {
  static const String baseUrl = 'https://soko-langu-server.onrender.com';

  /// Backend v2 (Trust-Commerce) base: all new endpoints live under /api/v1.
  /// Use v1('/auth/send-otp') instead of '$baseUrl/api/auth/send-otp'.
  static String v1(String path) => '$baseUrl/api/v1$path';

  /// Master test mode — false = production for all features (fraud, etc.)
  static const bool kIsTestMode = false;

  /// Ads-specific flag — false = production AdMob, true = test ads (dev only)
  static const bool kAdsTestMode = true;

  // OneSignal App ID from https://dashboard.onesignal.com
  static const String oneSignalAppId = '2e50d6a7-de2f-4b74-af36-4f1b0b28a1b2';
}
