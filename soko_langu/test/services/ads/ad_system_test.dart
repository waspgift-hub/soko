import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soko_vibe/models/seller_verification.dart';
import 'package:soko_vibe/services/ads/ad_config.dart';
import 'package:soko_vibe/services/ads/ad_eligibility_source.dart';
import 'package:soko_vibe/services/ads/ad_frequency_controller.dart';
import 'package:soko_vibe/services/ads/ad_remote_config.dart';
import 'package:soko_vibe/services/api_config.dart';

/// Shared builders for the ad-system tests.
///
/// The eligibility matrix is expressed as [SellerVerification] values built from
/// server-reported state only, which is exactly how production populates them —
/// there is no way to construct "exempt" without a genuine KYC approval plus an
/// ACTIVE admin grant.
class AdTestFixtures {
  const AdTestFixtures._();

  static SellerVerification buyer() => const SellerVerification(
        sellerId: 'buyer-1',
      );

  /// A seller who has never submitted KYC.
  static SellerVerification sellerNoKyc() => const SellerVerification(
        sellerId: 'seller-none',
        kycStatus: KycStatus.none,
      );

  static SellerVerification sellerPending() => const SellerVerification(
        sellerId: 'seller-pending',
        kycStatus: KycStatus.pending,
        blueTick: BlueTickStatus.pending,
      );

  static SellerVerification sellerRejected() => const SellerVerification(
        sellerId: 'seller-rejected',
        kycStatus: KycStatus.rejected,
      );

  static SellerVerification sellerRevokedKyc() => const SellerVerification(
        sellerId: 'seller-kyc-revoked',
        kycStatus: KycStatus.revoked,
      );

  /// KYC approved but the admin has not granted the tick. Still sees ads.
  static SellerVerification sellerApprovedNoTick() => const SellerVerification(
        sellerId: 'seller-approved',
        kycStatus: KycStatus.approved,
        kycApproved: true,
      );

  /// The only exempt state: KYC approved AND Blue Tick active.
  static SellerVerification blueTickSeller() => const SellerVerification(
        sellerId: 'seller-bluetick',
        kycStatus: KycStatus.approved,
        kycApproved: true,
        blueTick: BlueTickStatus.active,
      );

  /// Tick revoked after being granted.
  static SellerVerification revokedBlueTickSeller() => const SellerVerification(
        sellerId: 'seller-bluetick',
        kycStatus: KycStatus.approved,
        kycApproved: true,
        blueTick: BlueTickStatus.revoked,
      );

  /// Stale grant that survived a KYC revocation. Must NOT be exempt: this is the
  /// case that proves the tick is *derived*, not read straight off the document.
  static SellerVerification staleGrantAfterKycRevoke() => const SellerVerification(
        sellerId: 'seller-stale',
        kycStatus: KycStatus.revoked,
        blueTick: BlueTickStatus.active,
      );

  static AdRemoteConfig config({
    bool adsEnabled = true,
    bool blueTickExempt = true,
    double boost = 0.12,
  }) =>
      AdRemoteConfig(
        adsEnabled: adsEnabled,
        adsExemptBlueTickEnabled: blueTickExempt,
        searchVerifiedBoost: boost,
        maxSearchVerifiedBoost: 0.25,
        policy: AdFrequencyPolicy.defaults,
      );
}

/// Fresh [AdFrequencyController] on isolated preferences.
Future<AdFrequencyController> freshFrequency({
  AdFrequencyPolicy? policy,
  DateTime? now,
}) async {
  SharedPreferences.setMockInitialValues({});
  final controller =
      AdFrequencyController(policy: policy ?? AdFrequencyPolicy.defaults);
  await controller.beginSession(now: now);
  return controller;
}

/// A controller whose session started long enough ago that the launch grace
/// period has elapsed, so tests exercise the rule under test rather than the
/// grace window.
final DateTime kWellPastLaunch = DateTime(2026, 1, 1, 12, 0);
final DateTime kAfterLaunchGrace =
    kWellPastLaunch.add(const Duration(minutes: 10));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SellerVerification — Blue Tick derivation', () {
    test('blue tick requires KYC approved AND an active grant', () {
      expect(AdTestFixtures.blueTickSeller().isBlueTickActive, isTrue);
      expect(AdTestFixtures.blueTickSeller().isAdExempt, isTrue);
    });

    test('KYC approved without a grant is not exempt', () {
      final v = AdTestFixtures.sellerApprovedNoTick();
      expect(v.isBlueTickActive, isFalse);
      expect(v.isAdExempt, isFalse);
    });

    test('active grant with revoked KYC is not exempt (stale grant)', () {
      final v = AdTestFixtures.staleGrantAfterKycRevoke();
      expect(v.isBlueTickActive, isFalse,
          reason: 'the tick must be derived, not read off the document');
      expect(v.isAdExempt, isFalse);
    });

    test('revoked tick removes exemption', () {
      final v = AdTestFixtures.revokedBlueTickSeller();
      expect(v.isBlueTickActive, isFalse);
      expect(v.isAdExempt, isFalse);
    });

    test('kycApproved=true without status=approved is not exempt', () {
      const v = SellerVerification(
        sellerId: 'x',
        kycStatus: KycStatus.pending,
        kycApproved: true,
        blueTick: BlueTickStatus.active,
      );
      expect(v.isBlueTickActive, isFalse);
      expect(v.isAdExempt, isFalse);
    });

    test('parses a trusted passport envelope', () {
      final v = SellerVerification.fromPassport('s1', {
        'seller': {'storeName': 'Zuri', 'verificationStatus': 'verified'},
        'trust': {
          'blueTick': 'active',
          'kyc': {'status': 'approved', 'approved': true},
        },
      });
      expect(v.isBlueTickActive, isTrue);
      expect(v.storeName, 'Zuri');
    });

    test('parses a Firestore doc with timestamps converted to ISO', () {
      final v = SellerVerification.fromFirestoreDoc('s1', {
        'displayName': 'Zuri',
        'kyc': {'status': 'approved', 'approved': true},
        'trust': {
          'blueTick': 'active',
          'blueTickGrantedAt': '2026-01-01T00:00:00.000Z',
        },
      });
      expect(v.isBlueTickActive, isTrue);
      expect(v.grantedAt, isNotNull);
    });

    test('unknown state is treated as not exempt (fail-safe: ads stay on)', () {
      expect(SellerVerification.unknown.isAdExempt, isFalse);
    });
  });

  group('AdEligibilitySource matrix', () {
    test('only the Blue Tick seller is exempt', () {
      final cases = <String, SellerVerification>{
        'buyer': AdTestFixtures.buyer(),
        'seller-no-kyc': AdTestFixtures.sellerNoKyc(),
        'kyc-pending': AdTestFixtures.sellerPending(),
        'kyc-rejected': AdTestFixtures.sellerRejected(),
        'kyc-revoked': AdTestFixtures.sellerRevokedKyc(),
        'kyc-approved-no-tick': AdTestFixtures.sellerApprovedNoTick(),
        'blue-tick': AdTestFixtures.blueTickSeller(),
      };
      for (final entry in cases.entries) {
        final src = StaticAdEligibility(entry.value);
        expect(
          src.isSelfAdExempt,
          entry.key == 'blue-tick',
          reason: '${entry.key} exemption',
        );
      }
    });

    test('revocation propagates to listeners and clears the exemption', () {
      final src = StaticAdEligibility(AdTestFixtures.blueTickSeller());
      var notified = 0;
      void listener() => notified++;
      src.addListener(listener);

      expect(src.isSelfAdExempt, isTrue);
      src.updateSelf(AdTestFixtures.revokedBlueTickSeller());

      expect(notified, 1);
      expect(src.isSelfAdExempt, isFalse,
          reason: 'a revoked tick must restore normal advertising immediately');
      expect(src.isSelfBlueTick, isFalse);
    });

    test('badge lookup is false while unknown and true for a granted seller', () {
      final src = StaticAdEligibility(AdTestFixtures.buyer());
      expect(src.isBlueTick('unknown-seller'), isFalse);
      src.setOther(AdTestFixtures.blueTickSeller());
      expect(src.isBlueTick('seller-bluetick'), isTrue);
      src.setOther(AdTestFixtures.revokedBlueTickSeller());
      expect(src.isBlueTick('seller-bluetick'), isFalse);
    });
  });

  group('Critical-route suppression', () {
    test('every payment/KYC/OTP/dispute route is ad-free', () {
      for (final route in adCriticalRoutes) {
        expect(isAdCriticalRoute(route), isTrue, reason: route);
        expect(isAdCriticalRoute('$route/step-2'), isTrue, reason: route);
      }
    });

    test('ordinary marketplace routes are not critical', () {
      for (final route in ['/', '/search', '/category-products/phones', '/wishlist']) {
        expect(isAdCriticalRoute(route), isFalse, reason: route);
      }
    });

    test('null or empty location is not treated as critical', () {
      expect(isAdCriticalRoute(null), isFalse);
      expect(isAdCriticalRoute(''), isFalse);
    });
  });

  group('AdFrequencyController — eligibility and critical flows', () {
    test('blocks during checkout, payment, OTP and KYC', () async {
      final freq = await freshFrequency(now: kWellPastLaunch);
      for (final route in [
        '/checkout',
        '/order-detail/abc',
        '/boost-product',
        '/kyc',
        '/otp',
        '/report',
      ]) {
        final d = freq.canShowFullscreen(
          placement: AdPlacement.interstitialTabSwitch,
          adsEnabled: true,
          userEligible: true,
          sdkReady: true,
          adLoaded: true,
          currentRoute: route,
          now: kAfterLaunchGrace,
        );
        expect(d.allowed, isFalse, reason: route);
        expect(d.reason, AdSuppressionReason.criticalFlow, reason: route);
      }
      freq.dispose();
    });

    test('blocks an exempt (Blue Tick) user before touching any counter', () async {
      final freq = await freshFrequency(now: kWellPastLaunch);
      final d = freq.canShowFullscreen(
        placement: AdPlacement.interstitialTabSwitch,
        adsEnabled: true,
        userEligible: false,
        sdkReady: true,
        adLoaded: true,
        currentRoute: '/',
        now: kAfterLaunchGrace,
      );
      expect(d.allowed, isFalse);
      expect(d.reason, AdSuppressionReason.ineligibleUser);
      expect(freq.debugSessionInterstitials, 0);
      freq.dispose();
    });

    test('critical-flow suppression takes precedence over screen rules',
        () async {
      final freq = await freshFrequency(now: kWellPastLaunch);
      final d = freq.canShowFullscreen(
        placement: AdPlacement.interstitialSearchComplete,
        adsEnabled: true,
        userEligible: true,
        sdkReady: true,
        adLoaded: true,
        currentRoute: '/checkout',
        now: kAfterLaunchGrace,
      );
      expect(d.reason, AdSuppressionReason.criticalFlow);
      freq.dispose();
    });

    test('screens absent from the interstitial allow-list cannot interrupt',
        () async {
      // The invariant is expressed on the allow-list rather than on a placement:
      // a screen that is not opted in is silent until an admin opts it in.
      expect(interstitialCapableScreens.contains(AdScreen.profile), isFalse);
      expect(interstitialCapableScreens.contains(AdScreen.checkout), isFalse);
      expect(interstitialCapableScreens.contains(AdScreen.orders), isFalse);
      expect(interstitialCapableScreens.contains(AdScreen.messages), isFalse);
      for (final screen in [
        AdScreen.checkout,
        AdScreen.cart,
        AdScreen.orders,
        AdScreen.orderDetail,
        AdScreen.messages,
        AdScreen.chat,
        AdScreen.profile,
        AdScreen.notifications,
        AdScreen.music,
        AdScreen.aiAssistant,
      ]) {
        expect(interstitialCapableScreens.contains(screen), isFalse,
            reason: screen.name);
      }
    });
  });

  group('AdFrequencyController — frequency rules', () {
    test('never shows an interstitial inside the launch grace window', () async {
      final freq = await freshFrequency(now: kWellPastLaunch);
      final d = freq.canShowFullscreen(
        placement: AdPlacement.interstitialTabSwitch,
        adsEnabled: true,
        userEligible: true,
        sdkReady: true,
        adLoaded: true,
        currentRoute: '/',
        now: kWellPastLaunch.add(const Duration(seconds: 30)),
      );
      expect(d.allowed, isFalse);
      expect(d.reason, AdSuppressionReason.afterLaunchGrace);
      freq.dispose();
    });

    test('enforces the minimum interval between interstitials', () async {
      final freq = await freshFrequency(now: kWellPastLaunch);
      final placement = AdPlacement.interstitialTabSwitch;
      final first = kAfterLaunchGrace;

      expect(
        freq.canShowFullscreen(
          placement: placement,
          adsEnabled: true,
          userEligible: true,
          sdkReady: true,
          adLoaded: true,
          currentRoute: '/',
          now: first,
        ).allowed,
        isTrue,
      );
      freq.recordShown(placement, now: first);

      // Past the any-ad gap (2 min) but still inside the interstitial interval
      // (5 min), so the interval rule is the one under test.
      final tooSoon = freq.canShowFullscreen(
        placement: placement,
        adsEnabled: true,
        userEligible: true,
        sdkReady: true,
        adLoaded: true,
        currentRoute: '/',
        now: first.add(const Duration(minutes: 3)),
      );
      expect(tooSoon.allowed, isFalse);
      expect(tooSoon.reason, AdSuppressionReason.intervalNotElapsed);

      // Inside the any-ad gap, the stricter any-ad rule wins.
      final insideAnyAdGap = freq.canShowFullscreen(
        placement: placement,
        adsEnabled: true,
        userEligible: true,
        sdkReady: true,
        adLoaded: true,
        currentRoute: '/',
        now: first.add(const Duration(minutes: 1)),
      );
      expect(insideAnyAdGap.reason, AdSuppressionReason.afterAnyAdGap);

      final later = freq.canShowFullscreen(
        placement: placement,
        adsEnabled: true,
        userEligible: true,
        sdkReady: true,
        adLoaded: true,
        currentRoute: '/',
        now: first.add(const Duration(minutes: 6)),
      );
      expect(later.allowed, isTrue);
      freq.dispose();
    });

    test('refuses to show an interstitial immediately after another ad', () async {
      final freq = await freshFrequency(now: kWellPastLaunch);
      final first = kAfterLaunchGrace;
      freq.recordShown(AdPlacement.interstitialTabSwitch, now: first);

      final d = freq.canShowFullscreen(
        placement: AdPlacement.interstitialCategoryLeave,
        adsEnabled: true,
        userEligible: true,
        sdkReady: true,
        adLoaded: true,
        currentRoute: '/category/phones',
        now: first.add(const Duration(seconds: 10)),
      );
      expect(d.allowed, isFalse);
      expect(d.reason, AdSuppressionReason.afterAnyAdGap);
      freq.dispose();
    });

    test('enforces the per-session interstitial cap', () async {
      final freq = await freshFrequency(
        now: kWellPastLaunch,
        policy: const AdFrequencyPolicy(maxInterstitialsPerSession: 2),
      );
      final placement = AdPlacement.interstitialTabSwitch;
      var t = kAfterLaunchGrace;
      for (var i = 0; i < 2; i++) {
        expect(
          freq.canShowFullscreen(
            placement: placement,
            adsEnabled: true,
            userEligible: true,
            sdkReady: true,
            adLoaded: true,
            currentRoute: '/',
            now: t,
          ).allowed,
          isTrue,
        );
        freq.recordShown(placement, now: t);
        t = t.add(const Duration(minutes: 10));
      }

      final capped = freq.canShowFullscreen(
        placement: placement,
        adsEnabled: true,
        userEligible: true,
        sdkReady: true,
        adLoaded: true,
        currentRoute: '/',
        now: t,
      );
      expect(capped.allowed, isFalse);
      expect(capped.reason, AdSuppressionReason.sessionCap);
      freq.dispose();
    });

    test('enforces the per-session cap across all formats', () async {
      final freq = await freshFrequency(
        now: kWellPastLaunch,
        policy: const AdFrequencyPolicy(
          maxInterstitialsPerSession: 10,
          maxAdsPerSession: 3,
        ),
      );
      final t = kAfterLaunchGrace;
      for (var i = 0; i < 3; i++) {
        freq.recordShown(AdPlacement.interstitialTabSwitch, now: t);
      }
      expect(freq.debugSessionAds, 3);
      final d = freq.canShowInline(
        placement: AdPlacement.homeFeedFooter,
        adsEnabled: true,
        userEligible: true,
        currentRoute: '/',
        now: t.add(const Duration(minutes: 5)),
      );
      expect(d.allowed, isFalse);
      expect(d.reason, AdSuppressionReason.sessionCap);
      freq.dispose();
    });

    test('does not show an interstitial without a cached creative', () async {
      final freq = await freshFrequency(now: kWellPastLaunch);
      final d = freq.canShowFullscreen(
        placement: AdPlacement.interstitialTabSwitch,
        adsEnabled: true,
        userEligible: true,
        sdkReady: true,
        adLoaded: false,
        currentRoute: '/',
        now: kAfterLaunchGrace,
      );
      expect(d.allowed, isFalse);
      expect(d.reason, AdSuppressionReason.notLoaded);
      freq.dispose();
    });

    test('blocks when the SDK has not finished initializing', () async {
      final freq = await freshFrequency(now: kWellPastLaunch);
      final d = freq.canShowFullscreen(
        placement: AdPlacement.interstitialTabSwitch,
        adsEnabled: true,
        userEligible: true,
        sdkReady: false,
        adLoaded: true,
        currentRoute: '/',
        now: kAfterLaunchGrace,
      );
      expect(d.reason, AdSuppressionReason.sdkNotReady);
      freq.dispose();
    });

    test('blocks when the admin switch is off', () async {
      final freq = await freshFrequency(now: kWellPastLaunch);
      final d = freq.canShowFullscreen(
        placement: AdPlacement.interstitialTabSwitch,
        adsEnabled: false,
        userEligible: true,
        sdkReady: true,
        adLoaded: true,
        currentRoute: '/',
        now: kAfterLaunchGrace,
      );
      expect(d.reason, AdSuppressionReason.adsDisabled);
      freq.dispose();
    });
  });

  group('AdFrequencyController — failed loads', () {
    test('applies exponential backoff and stops after the hourly budget', () async {
      final freq = AdFrequencyController(
        policy: const AdFrequencyPolicy(
          maxLoadAttemptsPerHour: 2,
          retryBackoffBase: Duration(seconds: 30),
          maxRetryBackoff: Duration(minutes: 10),
        ),
      );
      await freq.beginSession(now: kWellPastLaunch);

      var t = kWellPastLaunch;
      // First failure: base delay.
      freq.recordLoadFailure('banner.home', now: t);
      var next = freq.nextAttemptAt('banner.home');
      expect(next, t.add(const Duration(seconds: 30)));

      // Second consecutive failure: doubled.
      t = next!;
      freq.recordLoadFailure('banner.home', now: t);
      next = freq.nextAttemptAt('banner.home');
      expect(next, t.add(const Duration(seconds: 60)));

      // Third exceeds maxLoadAttemptsPerHour, so the cap applies instead.
      t = next!;
      freq.recordLoadFailure('banner.home', now: t);
      next = freq.nextAttemptAt('banner.home');
      expect(next, t.add(const Duration(minutes: 10)));

      // A success clears the backoff entirely.
      freq.recordLoadSuccess('banner.home');
      expect(freq.nextAttemptAt('banner.home'), isNull);
      freq.dispose();
    });

    test('backoff survives a new session (persisted, not in-memory)', () async {
      final freq = AdFrequencyController(
        policy: const AdFrequencyPolicy(
          maxLoadAttemptsPerHour: 100,
          retryBackoffBase: Duration(seconds: 30),
        ),
      );
      await freq.beginSession(now: kWellPastLaunch);
      freq.recordLoadFailure('banner.x', now: kWellPastLaunch);
      expect(freq.nextAttemptAt('banner.x'), isNotNull);

      // Simulate an app restart: a brand new controller on the same storage.
      final restarted = AdFrequencyController(
        policy: const AdFrequencyPolicy(
          maxLoadAttemptsPerHour: 100,
          retryBackoffBase: Duration(seconds: 30),
        ),
      );
      await restarted.beginSession(now: kWellPastLaunch);
      expect(
        restarted.nextAttemptAt('banner.x'),
        isNotNull,
        reason: 'force-quitting must not reset the retry budget',
      );
      freq.dispose();
      restarted.dispose();
    });
  });

  group('AdFrequencyController — account isolation', () {
    test('switching accounts resets counters and namespaces the storage', () async {
      SharedPreferences.setMockInitialValues({});
      final freq = AdFrequencyController();
      await freq.beginSession(now: kWellPastLaunch);
      await freq.adoptAccount('account-a');
      freq.recordShown(AdPlacement.interstitialTabSwitch, now: kAfterLaunchGrace);
      expect(freq.debugSessionInterstitials, 1);

      await freq.adoptAccount('account-b');
      expect(
        freq.debugSessionInterstitials,
        0,
        reason: 'a second account must not inherit the first account session',
      );

      // And account A's persisted state is untouched, so switching back keeps
      // its own (capped) counters rather than starting fresh.
      await freq.adoptAccount('account-a');
      expect(freq.debugSessionInterstitials, 0);
      freq.dispose();
    });

    test('a different account never inherits the ad exemption', () async {
      final a = StaticAdEligibility(AdTestFixtures.blueTickSeller());
      expect(a.isSelfAdExempt, isTrue);

      // Logging out resets to unknown, which is NOT exempt: ads come back.
      final loggedOut = StaticAdEligibility();
      expect(loggedOut.isSelfAdExempt, isFalse);

      // A fresh non-verified account is not exempt either.
      final b = StaticAdEligibility(AdTestFixtures.sellerPending());
      expect(b.isSelfAdExempt, isFalse);
    });

    test('signing out resets session counters', () async {
      SharedPreferences.setMockInitialValues({});
      final freq = AdFrequencyController();
      await freq.beginSession(now: kWellPastLaunch);
      await freq.adoptAccount('account-a');
      freq.recordShown(AdPlacement.interstitialTabSwitch, now: kAfterLaunchGrace);
      expect(freq.debugSessionAds, 1);

      await freq.adoptAccount(null);
      expect(freq.debugSessionAds, 0);
      freq.dispose();
    });
  });

  group('AdFrequencyController — rewarded gate', () {
    test('gate persists and expires by TTL instead of never resetting', () async {
      SharedPreferences.setMockInitialValues({});
      final freq = AdFrequencyController(
        policy: const AdFrequencyPolicy(gateTtl: Duration(milliseconds: 50)),
      );
      await freq.beginSession();

      expect(await freq.hasPassedGate('unlock_1'), isFalse);
      await freq.markGatePassed('unlock_1');
      expect(await freq.hasPassedGate('unlock_1'), isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(
        await freq.hasPassedGate('unlock_1'),
        isFalse,
        reason: 'a gate must expire, otherwise the unlock is permanent',
      );
      freq.dispose();
    });

    test('resetGate clears a passed gate', () async {
      SharedPreferences.setMockInitialValues({});
      final freq = AdFrequencyController();
      await freq.beginSession();
      await freq.markGatePassed('x');
      await freq.resetGate('x');
      expect(await freq.hasPassedGate('x'), isFalse);
      freq.dispose();
    });
  });

  group('AdRemoteConfig — admin toggles', () {
    test('master switch disables every placement', () {
      final off = AdRemoteConfig.fromMap({'adsEnabled': false});
      expect(off.isPlacementEnabled(AdPlacement.homeFeedFooter), isFalse);
      expect(off.isPlacementEnabled(AdPlacement.interstitialTabSwitch), isFalse);
    });

    test('per-format switches disable only that format', () {
      final cfg = AdRemoteConfig.fromMap({'bannerEnabled': false});
      expect(cfg.isPlacementEnabled(AdPlacement.homeFeedFooter), isFalse);
      expect(cfg.isPlacementEnabled(AdPlacement.interstitialTabSwitch), isTrue);
    });

    test('per-placement disable list is honoured', () {
      final cfg = AdRemoteConfig.fromMap({
        'disabledPlacements': ['home.feed.footer'],
      });
      expect(cfg.isPlacementEnabled(AdPlacement.homeFeedFooter), isFalse);
      expect(cfg.isPlacementEnabled(AdPlacement.wishlistFooter), isTrue);
    });

    test('per-screen disable list is honoured', () {
      final cfg = AdRemoteConfig.fromMap({'disabledScreens': ['productDetail']});
      expect(cfg.isPlacementEnabled(AdPlacement.productDetailReviews), isFalse);
      expect(cfg.isPlacementEnabled(AdPlacement.profileFooter), isTrue);
    });

    test('Blue Tick exemption can be turned off globally', () {
      final cfg = AdRemoteConfig.fromMap({'adsExemptBlueTickEnabled': false});
      expect(cfg.adsExemptBlueTickEnabled, isFalse);
    });

    test('the search boost is clamped to the admin ceiling', () {
      final cfg = AdRemoteConfig.fromMap({
        'searchVerifiedBoost': 0.9,
        'maxSearchVerifiedBoost': 0.25,
      });
      expect(cfg.searchVerifiedBoost, lessThanOrEqualTo(0.25));
    });

    test('outranking relevance stays off unless explicitly enabled', () {
      expect(AdRemoteConfig.fromMap({}).allowBoostToOutrankRelevance, isFalse);
      expect(
        AdRemoteConfig.fromMap({'allowBoostToOutrankRelevance': true})
            .allowBoostToOutrankRelevance,
        isTrue,
      );
    });

    test('malformed or empty remote data falls back to safe defaults', () {
      final fromNull = AdRemoteConfig.fromMap(null);
      expect(fromNull.adsEnabled, isTrue);
      expect(fromNull.adsExemptBlueTickEnabled, isTrue);
      expect(fromNull.searchVerifiedBoost, greaterThanOrEqualTo(0.0));

      final garbage = AdRemoteConfig.fromMap({
        'adsEnabled': 'yes',
        'searchVerifiedBoost': 'not-a-number',
        'frequency': 'nope',
      });
      expect(garbage.adsEnabled, isTrue,
          reason: 'a non-boolean must not be read as false and kill ads');
      expect(garbage.policy, AdFrequencyPolicy.defaults);
    });

    test('frequency overrides round-trip through toMap', () {
      const policy = AdFrequencyPolicy(
        maxInterstitialsPerSession: 7,
        minIntervalBetweenInterstitials: Duration(minutes: 11),
      );
      final cfg = AdRemoteConfig(policy: policy);
      final parsed = AdRemoteConfig.fromMap(cfg.toMap());
      expect(parsed.policy.maxInterstitialsPerSession, 7);
      expect(parsed.policy.minIntervalBetweenInterstitials, const Duration(minutes: 11));
    });
  });

  group('AdUnitIds — test vs production', () {
    test('the publisher IDs are the configured AdMob units', () {
      // Suffixes must match the AdMob console for pub-3796499857968162.
      expect(AdUnitIds.bannerProd, 'ca-app-pub-3796499857968162/6300978111');
      expect(AdUnitIds.interstitialProd,
          'ca-app-pub-3796499857968162/1033173712');
      expect(AdUnitIds.rewardedProd, 'ca-app-pub-3796499857968162/5224354917');
    });

    test('test mode resolves to Google sample units', () {
      expect(AdUnitIds.banner(test: true),
          startsWith('ca-app-pub-3940256099942544'));
      expect(AdUnitIds.interstitial(test: true),
          startsWith('ca-app-pub-3940256099942544'));
      expect(AdUnitIds.rewarded(test: true),
          startsWith('ca-app-pub-3940256099942544'));
    });

    test('the default follows the existing development/test configuration', () {
      // Deliberately does NOT assert "production": the repo ships with
      // ApiConfig.kAdsTestMode = true and the brief is to keep using the
      // existing test configuration rather than flipping production IDs.
      // What matters is that the default tracks that flag and can be overridden
      // per build with --dart-define=ADS_TEST_MODE.
      expect(
        AdUnitIds.banner(),
        ApiConfig.kAdsTestMode ? AdUnitIds.bannerTest : AdUnitIds.bannerProd,
        reason: 'the default must track the configured test/production mode',
      );
      expect(AdUnitIds.testMode, ApiConfig.kAdsTestMode);
    });

    test('an explicit test:true always wins over the configured mode', () {
      expect(AdUnitIds.banner(test: true), AdUnitIds.bannerTest);
      expect(AdUnitIds.interstitial(test: true), AdUnitIds.interstitialTest);
      expect(AdUnitIds.rewarded(test: true), AdUnitIds.rewardedTest);
      expect(AdUnitIds.native(test: true), AdUnitIds.nativeTest);
    });

    test('every format has a distinct test and production unit', () {
      for (final pair in [
        [AdUnitIds.bannerTest, AdUnitIds.bannerProd],
        [AdUnitIds.interstitialTest, AdUnitIds.interstitialProd],
        [AdUnitIds.rewardedTest, AdUnitIds.rewardedProd],
        [AdUnitIds.nativeTest, AdUnitIds.nativeProd],
      ]) {
        expect(pair[0], isNot(pair[1]));
        expect(pair[0], isNotEmpty);
        expect(pair[1], isNotEmpty);
      }
    });

    test('ads.txt is published for the same publisher', () {
      expect(AdUnitIds.adsTxtRecord, contains('pub-3796499857968162'));
    });
  });

  group('AdPlacement registry', () {
    test('placement ids are unique and stable', () {
      final ids = AdPlacement.values.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('no inline placement targets a critical screen', () {
      for (final p in AdPlacement.values) {
        expect(p.screen, isNot(AdScreen.checkout),
            reason: '${p.id} must not be a checkout placement');
      }
    });

    test('fullscreen placements are exactly the interstitial and rewarded set',
        () {
      final fullscreen = AdPlacement.values.where((p) => p.isFullscreen).toSet();
      expect(fullscreen, {
        AdPlacement.interstitialTabSwitch,
        AdPlacement.interstitialSearchComplete,
        AdPlacement.interstitialCategoryLeave,
        AdPlacement.interstitialSellerPageLeave,
        AdPlacement.rewardedUnlockContact,
        AdPlacement.rewardedCreateFlashSale,
      });
    });

    test('interstitial placements only target opted-in screens', () {
      for (final p in AdPlacement.values.where((x) => x.format == AdFormat.interstitial)) {
        expect(interstitialCapableScreens.contains(p.screen), isTrue,
            reason: p.id);
      }
    });
  });
}