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

  /// Phase D categories bridge switch: when true, the home category grid and
  /// category pages resolve categories from /api/v1/products/categories
  /// (Postgres, UUID ids) instead of the Firestore `categories` collection.
  /// Flipped true after the 12-category seed landed — `kUseProductsApi` already
  /// routes the category product lists through the catalog list API, which
  /// resolves legacy category names to the Postgres uuid server-side.
  static const bool kUseCategoriesApi = true;

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

  /// Phase F (R2/MEDIA) bridge switch: when true, product image/video uploads
  /// go through `r2_media_service.dart` using the `/api/v1/media/upload-url`
  /// presigned PUT flow (media bytes go straight to Cloudflare R2, no
  /// Cloudinary credentials ever touch the client) with `r2PublicUrl` as the
  /// public read base — mirroring the `CloudinaryService` API so callers swap
  /// via one const. Flipped true only after the R2 evidence/media backfill
  /// lands in production and the media queue (thumbnails/video-transcode) is
  /// verified on live buckets. Until then uploads stay on Cloudinary.
  static const bool kUseMediaApi = false;

  /// Public read origin for R2 media (server: `R2_PUBLIC_URL`, served through
  /// the media CDN edge). Objects live at `<r2PublicUrl>/<kind>/<key>`.
  /// Since `kUseMediaApi` stays OFF until the R2 media backfill, this base is
  /// unused by current production flows.
  static const String r2PublicUrl = 'https://media.sokovibe.co.tz';

  /// Phase D user-profile bridge switch: when true, the current user's profile
  /// read/write (/api/v1/users/me) and other users' public profiles
  /// (/api/v1/users/public/:id) come from Postgres with Firestore as the
  /// degraded fallback. Firestore stays the source for realtime presence
  /// (lastActive/activeChatRoom streams), username search, and the direct
  /// register/profile_setup doc writes until Phase D2.
  static const bool kUseUsersApi = true;

  /// Phase E comments bridge switch: when true, product comments (add/reply/
  /// list/delete) go through /api/v1/products/:id/comments (Postgres,
  /// Comment.targetId is VarChar so legacy opaque product ids resolve via
  /// snapshot.legacyId) with Firestore as the degraded fallback. The live
  /// stream becomes a short polling refresh so the widget API stays `Stream`.
  static const bool kUseCommentsApi = true;

  /// Master test mode — false = production for all features (fraud, etc.)
  static const bool kIsTestMode = false;

  /// Ads-specific flag — false = production AdMob, true = test ads (dev only)
  static const bool kAdsTestMode = false;

  // OneSignal App ID from https://dashboard.onesignal.com
  static const String oneSignalAppId = '2e50d6a7-de2f-4b74-af36-4f1b0b28a1b2';
}