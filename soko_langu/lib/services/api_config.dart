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

  /// Phase B/C order bridge switch: when true, lifecycle mutations go through
  /// [OrderApiClient] to /api/v1/orders (Postgres state machine) instead of the
  /// legacy Firestore compat handlers. Keep false until server-side mirror +
  /// app-status-compat review is signed off (app orders start in
  /// AWAITING_ESCROW_PAYMENT, which differs from the v1 createOrder chain).
  static const bool kUseOrdersApi = false;

  /// Phase B/C wallet bridge switch: when true, seller withdrawal UIs read the
  /// Postgres wallet (/api/v1/wallet) instead of legacy Firestore sellerBalance
  /// payouts. Keep false until the release-path converge lands, otherwise app
  /// sellers would see an empty wallet (their money still lives in Firestore).
  static const bool kUseWalletApi = false;

  /// Phase B notifications bridge switch: when true, the in-app notification
  /// center reads from /api/v1/notifications (Postgres) instead of Firestore.
  /// Push delivery (OneSignal) is unchanged; only the persistent inbox migrates.
  static const bool kUseNotificationsApi = false;

  /// Phase C trust bridge switch: when true, TrustPassportCard reads the seller
  /// trust passport from /api/v1/trust/sellers/:id/passport (Postgres) instead
  /// of the legacy Firestore compat endpoint /api/trust/passport/:id. The v1
  /// endpoint resolves sellers by Firebase UID (SellerProfile.userId) as well
  /// as by Postgres UUID, so app order-detail sellerId (a Firebase UID) works
  /// unchanged. Keep false until product/order backfill + verification flows
  /// are live in production, otherwise passports show near-empty metrics.
  static const bool kUseTrustApi = false;

  /// Master test mode — false = production for all features (fraud, etc.)
  static const bool kIsTestMode = false;

  /// Ads-specific flag — false = production AdMob, true = test ads (dev only)
  static const bool kAdsTestMode = true;

  // OneSignal App ID from https://dashboard.onesignal.com
  static const String oneSignalAppId = '2e50d6a7-de2f-4b74-af36-4f1b0b28a1b2';
}
