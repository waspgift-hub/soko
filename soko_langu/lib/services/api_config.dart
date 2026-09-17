class ApiConfig {
  // Edge-cached via the Cloudflare Worker (soko-api-edge); the Render origin
  // is only hit on a worker cache miss.
  static const String baseUrl = 'https://api.sokovibe.co.tz';

  /// Backend v2 (Trust-Commerce) base: all new endpoints live under /api/v1.
  /// Use v1('/auth/send-otp') instead of '$baseUrl/api/auth/send-otp'.
  static String v1(String path) => '$baseUrl/api/v1$path';

  /// Phase C bridge switch: when true, the catalog feed reads from the v2 API
  /// (/api/v1/products, Postgres) and falls back to Firestore. Flipped true on
  /// 2026-09-17 after the Firestore→Postgres product backfill ran in production
  /// (7 products live); repository callers still fall back to Firestore/cache.
  static const bool kUseProductsApi = true;

  /// Phase B/C order bridge switch: when true, lifecycle mutations go through
  /// [OrderApiClient] to /api/v1/orders (Postgres state machine) instead of the
  /// legacy Firestore compat handlers. Flipped true after the escrow-orders
  /// backfill (42 orders live), the seller-balance cutover, and the OTP release
  /// path (handover issueOtp + verifyOtpAndComplete) shipped together with the
  /// wallet flip. Cancel and dispute intentionally stay on legacy compat.
  static const bool kUseOrdersApi = true;

  /// Phase B/C wallet bridge switch: when true, seller withdrawal UIs read the
  /// Postgres wallet (/api/v1/wallet) instead of legacy Firestore sellerBalance
  /// payouts. Flipped true on the coordinated release flip: the seller-balance
  /// cutover ran (0 eligible TZS in Firestore), ensureWallet guards settlement,
  /// and withdrawals.phone_number exists in Postgres.
  static const bool kUseWalletApi = true;

  /// Phase B notifications bridge switch: when true, the in-app notification
  /// center reads from /api/v1/notifications (Postgres) instead of Firestore.
  /// Push delivery (OneSignal) is unchanged; only the persistent inbox migrates.
  /// Flipped true after the 369-row notifications backfill landed in production.
  static const bool kUseNotificationsApi = true;

  /// Phase C trust bridge switch: when true, TrustPassportCard reads the seller
  /// trust passport from /api/v1/trust/sellers/:id/passport (Postgres) instead
  /// of the legacy Firestore compat endpoint /api/trust/passport/:id. The v1
  /// endpoint resolves sellers by Firebase UID (SellerProfile.userId) as well
  /// as by Postgres UUID, so app order-detail sellerId (a Firebase UID) works
  /// unchanged. Flipped true after the product/order backfill + verification
  /// flows went live in production.
  static const bool kUseTrustApi = true;

  /// Phase C search bridge switch: when true, the search screen's product
  /// results are fetched from /api/v1/search/products (Postgres) first, with
  /// the legacy /api/search/global-search + Firestore fallback intact.
  /// Flipped true after the product backfill ran (Postgres catalog is live).
  static const bool kUseSearchApi = true;

  /// Phase D reviews bridge switch: when true, review reads/writes go through
  /// /api/v1/reviews (Postgres) instead of the Firestore `reviews` collection.
  /// List reads become one-shot fetches (the v1 API is HTTP, not a stream);
  /// writes upsert by (userId, productId), and "helpful" + seller replies route
  /// to the API too. Flipped true after the product backfill (7 live) and the
  /// 20-row reviews backfill (opaque legacy product ids survive both eras).
  static const bool kUseReviewsApi = true;

  /// Phase D KYC bridge switch: when true, the seller KYC submission and status
  /// reads go through /api/v1/kyc (Postgres) instead of the Firestore
  /// users/{uid}.kyc embedded doc. Flipped true after `prisma db push` created
  /// kyc_applications in production and the 1 approved application was
  /// backfilled; admin panel stays on legacy /api/admin/kyc/*.
  static const bool kUseKycApi = true;

  /// Master test mode — false = production for all features (fraud, etc.)
  static const bool kIsTestMode = false;

  /// Ads-specific flag — false = production AdMob, true = test ads (dev only)
  static const bool kAdsTestMode = true;

  // OneSignal App ID from https://dashboard.onesignal.com
  static const String oneSignalAppId = '2e50d6a7-de2f-4b74-af36-4f1b0b28a1b2';
}