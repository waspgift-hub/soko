class ApiConfig {
  // Edge-cached via the Cloudflare Worker (soko-api-edge); the Render origin
  // is only hit on a worker cache miss.
  static const String baseUrl = 'https://api.sokovibe.co.tz';

  /// Backend v2 (Trust-Commerce) base: all new endpoints live under /api/v1.
  /// Use v1('/auth/send-otp') instead of '$baseUrl/api/auth/send-otp'.
  static String v1(String path) => '$baseUrl/api/v1$path';

  /// Phase C bridge switch: when true, the catalog feed reads from the v2 API
  /// (/api/v1/products, Postgres) before falling back to Firestore. Keep false
  /// until the Firestore→Postgres product backfill has run in production.
  static const bool kUseProductsApi = false;

  /// Master test mode — false = production for all features (fraud, etc.)
  static const bool kIsTestMode = false;

  /// Ads-specific flag — false = production AdMob, true = test ads (dev only)
  static const bool kAdsTestMode = true;

  // OneSignal App ID from https://dashboard.onesignal.com
  static const String oneSignalAppId = '2e50d6a7-de2f-4b74-af36-4f1b0b28a1b2';
}
