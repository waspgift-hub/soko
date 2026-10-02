import 'package:flutter/foundation.dart';

import '../api_config.dart';

/// Canonical AdMob ad-unit identifiers for the Soko Vibe publisher account.
///
/// The production suffixes are the ones already configured in the AdMob console
/// for `pub-3796499857968162`; the test suffixes are Google's public sample units
/// so a misconfigured build can never serve real inventory by accident.
///
/// Test mode is resolved from `--dart-define=ADS_TEST_MODE=...` first and only
/// then from [ApiConfig.kAdsTestMode]. That keeps `flutter build` reproducible
/// without editing source while preserving the existing in-repo default.
class AdUnitIds {
  AdUnitIds._();

  static const String _publisher = 'ca-app-pub-3796499857968162';
  static const String _testPublisher = 'ca-app-pub-3940256099942544';

  static const String bannerProd = '$_publisher/6300978111';
  static const String bannerTest = '$_testPublisher/6300978111';

  static const String interstitialProd = '$_publisher/1033173712';
  static const String interstitialTest = '$_testPublisher/1033173712';

  static const String rewardedProd = '$_publisher/5224354917';
  static const String rewardedTest = '$_testPublisher/5224354917';

  static const String nativeProd = '$_publisher/2247696110';
  static const String nativeTest = '$_testPublisher/2247696110';

  /// `ads.txt` line for the app's first-party web domain, published to
  /// `hosting/ads.txt`. Android ships a bundled copy in app assets.
  static const String adsTxtRecord =
      'google.com, pub-3796499857968162, DIRECT, f08c47fec0942fa0';

  static const bool _defineTestMode =
      bool.fromEnvironment('ADS_TEST_MODE', defaultValue: false);

  /// True when Google test inventory should be used. `dart-define` wins so CI
  /// and release pipelines can flip it without a code change.
  static bool get testMode => _defineTestMode || ApiConfig.kAdsTestMode;

  static String banner({bool test = false}) =>
      (test || testMode) ? bannerTest : bannerProd;

  static String interstitial({bool test = false}) =>
      (test || testMode) ? interstitialTest : interstitialProd;

  static String rewarded({bool test = false}) =>
      (test || testMode) ? rewardedTest : rewardedProd;

  static String native({bool test = false}) =>
      (test || testMode) ? nativeTest : nativeProd;
}

/// Ad formats the manager can serve.
enum AdFormat { banner, native, interstitial, rewarded }

/// Every screen the ad system is allowed to reason about. Placements are keyed
/// to these so remote config can enable or disable a format per screen without
/// a client release.
enum AdScreen {
  home,
  search,
  searchResults,
  categories,
  categoryProducts,
  productDetail,
  sellerProfile,
  cart,
  checkout,
  orders,
  orderDetail,
  messages,
  chat,
  profile,
  music,
  aiAssistant,
  notifications,
  wishlist,
  flashSale,
  feed,
  unknown,
}

/// A named, centrally registered ad placement.
///
/// Screens reference placements by enum value only. Anything the AdManager needs
/// to decide — format, screen, whether it is safe to fire a fullscreen ad from
/// here, how it must be separated from other ads — is declared once here.
enum AdPlacement {
  homeFeedFooter,
  homeFeedMid,
  searchResultsFooter,
  searchResultsMid,
  categoriesFooter,
  categoryProductsFooter,
  productDetailFooter,
  productDetailReviews,
  sellerProfileFooter,
  cartFooter,
  ordersFooter,
  notificationsFooter,
  profileFooter,
  wishlistFooter,
  flashSaleFooter,
  musicFeedFooter,
  interstitialTabSwitch,
  interstitialSearchComplete,
  interstitialCategoryLeave,
  interstitialSellerPageLeave,
  rewardedUnlockContact,
  rewardedCreateFlashSale;

  String get id => switch (this) {
        AdPlacement.homeFeedFooter => 'home.feed.footer',
        AdPlacement.homeFeedMid => 'home.feed.mid',
        AdPlacement.searchResultsFooter => 'search.results.footer',
        AdPlacement.searchResultsMid => 'search.results.mid',
        AdPlacement.categoriesFooter => 'categories.footer',
        AdPlacement.categoryProductsFooter => 'category.products.footer',
        AdPlacement.productDetailFooter => 'product.detail.footer',
        AdPlacement.productDetailReviews => 'product.detail.after_reviews',
        AdPlacement.sellerProfileFooter => 'seller.profile.footer',
        AdPlacement.cartFooter => 'cart.footer',
        AdPlacement.ordersFooter => 'orders.footer',
        AdPlacement.notificationsFooter => 'notifications.footer',
        AdPlacement.profileFooter => 'profile.footer',
        AdPlacement.wishlistFooter => 'wishlist.footer',
        AdPlacement.flashSaleFooter => 'flashsale.footer',
        AdPlacement.musicFeedFooter => 'music.feed.footer',
        AdPlacement.interstitialTabSwitch => 'interstitial.tab_switch',
        AdPlacement.interstitialSearchComplete =>
          'interstitial.search_complete',
        AdPlacement.interstitialCategoryLeave => 'interstitial.category_leave',
        AdPlacement.interstitialSellerPageLeave =>
          'interstitial.seller_page_leave',
        AdPlacement.rewardedUnlockContact => 'rewarded.unlock_contact',
        AdPlacement.rewardedCreateFlashSale => 'rewarded.create_flash_sale',
      };

  AdFormat get format => switch (this) {
        AdPlacement.interstitialTabSwitch ||
        AdPlacement.interstitialSearchComplete ||
        AdPlacement.interstitialCategoryLeave ||
        AdPlacement.interstitialSellerPageLeave =>
          AdFormat.interstitial,
        AdPlacement.rewardedUnlockContact ||
        AdPlacement.rewardedCreateFlashSale =>
          AdFormat.rewarded,
        _ => AdFormat.banner,
      };

  AdScreen get screen => switch (this) {
        AdPlacement.homeFeedFooter || AdPlacement.homeFeedMid => AdScreen.home,
        AdPlacement.searchResultsFooter ||
        AdPlacement.searchResultsMid ||
        AdPlacement.interstitialSearchComplete =>
          AdScreen.searchResults,
        AdPlacement.categoriesFooter ||
        AdPlacement.interstitialCategoryLeave =>
          AdScreen.categories,
        AdPlacement.categoryProductsFooter => AdScreen.categoryProducts,
        AdPlacement.productDetailFooter ||
        AdPlacement.productDetailReviews =>
          AdScreen.productDetail,
        AdPlacement.sellerProfileFooter ||
        AdPlacement.interstitialSellerPageLeave =>
          AdScreen.sellerProfile,
        AdPlacement.cartFooter => AdScreen.cart,
        AdPlacement.ordersFooter => AdScreen.orders,
        AdPlacement.notificationsFooter => AdScreen.notifications,
        AdPlacement.profileFooter => AdScreen.profile,
        AdPlacement.wishlistFooter => AdScreen.wishlist,
        AdPlacement.flashSaleFooter => AdScreen.flashSale,
        AdPlacement.rewardedCreateFlashSale => AdScreen.flashSale,
        AdPlacement.rewardedUnlockContact => AdScreen.messages,
        AdPlacement.musicFeedFooter => AdScreen.music,
        AdPlacement.interstitialTabSwitch => AdScreen.unknown,
      };

  /// True for placements that must never run while a fullscreen ad, a rewarded
  /// gate dialog, or a critical marketplace flow is on screen.
  bool get isFullscreen => format == AdFormat.interstitial ||
      format == AdFormat.rewarded;

  /// True when the placement sits inside a scrollable feed, so the manager can
  /// keep it out of the first screenful and space it away from neighbours.
  bool get isInFeed => this == AdPlacement.homeFeedMid ||
      this == AdPlacement.searchResultsMid;
}

/// Screens where no ad of any format may render, plus the navigation-triggered
/// interstitial transition points that are deliberately not treated as ads.
const Set<AdScreen> adFreeScreens = {
  AdScreen.checkout,
};

/// Routes that must never host an ad. Matched as a prefix against the current
/// GoRouter location so a deep link into a payment sub-screen is covered too.
///
/// Interstitials are suppressed while any of these is on top, which is the
/// mechanism that prevents an ad from ever landing on top of a payment sheet,
/// OTP entry, KYC review or dispute form.
const List<String> adCriticalRoutes = [
  '/checkout',
  '/order-detail',
  '/boost-product',
  '/kyc',
  '/otp',
  '/login',
  '/register',
  '/forgot-password',
  '/verify-email',
  '/seller-earnings',
  '/seller-dispatch',
  '/seller-quote',
  '/report',
  '/create-buyer-request',
  '/post-buyer-request',
  '/create-flash-sale',
  '/receipt',
  '/now-playing',
  '/privacy-policy',
  '/terms-of-service',
  '/admin',
];

/// Screens where a fullscreen ad is allowed to interrupt. Anything absent is
/// treated as forbidden, so a new screen is ad-free until it is opted in.
///
/// [AdScreen.unknown] is present because the shell's tab-switch interstitial is
/// not owned by any one screen. It is still safe: the critical-route check runs
/// first, so a tab switch performed while a pushed checkout or payment screen is
/// on top is still blocked.
const Set<AdScreen> interstitialCapableScreens = {
  AdScreen.home,
  AdScreen.searchResults,
  AdScreen.categories,
  AdScreen.categoryProducts,
  AdScreen.sellerProfile,
  AdScreen.unknown,
};

/// Whether the current GoRouter location is a critical marketplace flow.
bool isAdCriticalRoute(String? location) {
  if (location == null || location.isEmpty) return false;
  for (final route in adCriticalRoutes) {
    if (location == route || location.startsWith('$route/')) return true;
  }
  return false;
}

/// Debug-only assertion used by the AdSlot widget and by tests: an inline
/// placement must never be mounted inside a critical flow.
@visibleForTesting
bool placementAllowedOnRoute(AdPlacement placement, String? location) =>
    !isAdCriticalRoute(location);
