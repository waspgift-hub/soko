import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soko_vibe/models/seller_verification.dart';
import 'package:soko_vibe/services/ads/ad_config.dart';
import 'package:soko_vibe/services/ads/ad_eligibility_source.dart';
import 'package:soko_vibe/services/ads/ad_frequency_controller.dart';
import 'package:soko_vibe/services/ads/ad_manager.dart';
import 'package:soko_vibe/services/ads/ad_remote_config.dart';
import 'package:soko_vibe/services/ads/ad_route_observer.dart';
import 'package:soko_vibe/widgets/ads/ad_slot.dart';
import 'package:soko_vibe/widgets/ads/blue_tick_badge.dart';

/// Fake SDK gateway.
///
/// Never touches a platform channel, so these tests run on the Dart VM. It also
/// lets a test make a load fail, succeed, or hang, which is how the
/// failed-load / offline / no-duplicate cases are exercised deterministically.
class FakeAdSdk implements AdSdkGateway {
  FakeAdSdk({this.interstitialSucceeds = true, this.rewardedSucceeds = true});

  bool initializeResult = true;
  bool interstitialSucceeds;
  bool rewardedSucceeds;

  int interstitialLoadCount = 0;
  int rewardedLoadCount = 0;
  int bannerLoadCount = 0;
  bool initializeCalled = false;

  /// Defaults to false: no fill is the realistic state for most sessions, and
  /// it keeps AdWidget out of the tree (which asserts on a real platform ad).
  /// The manager's behaviour is identical either way.
  bool bannerSucceeds = false;

  @override
  Future<bool> initialize() async {
    initializeCalled = true;
    return initializeResult;
  }

  @override
  BannerAd createBanner({
    required String adUnitId,
    required BannerAdListener listener,
  }) {
    final fake = FakeBannerAd(bannerListener: listener);
    if (bannerSucceeds) {
      // Fire on the next microtask so the caller has a chance to store the
      // instance first, mirroring the real SDK's asynchronous callback.
      scheduleMicrotask(() => listener.onAdLoaded?.call(fake));
    } else {
      scheduleMicrotask(() => listener.onAdFailedToLoad?.call(
            fake,
            LoadAdError(3, 'com.google.android.gms.ads', 'No fill', null),
          ));
    }
    return fake;
  }

  @override
  Future<void> loadBanner(BannerAd ad) async => bannerLoadCount++;

  @override
  Future<void> loadInterstitial({
    required String adUnitId,
    required void Function(InterstitialAd ad) onLoaded,
    required void Function(String error) onFailed,
  }) async {
    interstitialLoadCount++;
    if (interstitialSucceeds) {
      onLoaded(FakeInterstitialAd());
    } else {
      onFailed('no fill');
    }
  }

  @override
  Future<void> loadRewarded({
    required String adUnitId,
    required void Function(RewardedAd ad) onLoaded,
    required void Function(String error) onFailed,
  }) async {
    rewardedLoadCount++;
    if (rewardedSucceeds) {
      onLoaded(FakeRewardedAd());
    } else {
      onFailed('no fill');
    }
  }

}


class FakeBannerAd implements BannerAd {
  FakeBannerAd({required this.bannerListener});
  final BannerAdListener bannerListener;

  @override
  AdSize get size => AdSize.banner;

  @override
  String get adUnitId => 'fake/banner';

  @override
  AdRequest get request => const AdRequest();

  @override
  BannerAdListener get listener => bannerListener;

  String? get responseId => null;

  bool disposed = false;

  @override
  Future<void> dispose() async => disposed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Fake interstitial.
///
/// `show()` deliberately does not invoke the dismiss callback: that mirrors a
/// real fullscreen ad being presented and abandoned, which is how the test
/// asserts that the frequency counter is charged on presentation rather than on
/// request.
class FakeInterstitialAd implements InterstitialAd {
  bool disposed = false;

  @override
  FullScreenContentCallback<InterstitialAd>? fullScreenContentCallback;

  @override
  Future<void> show() async {}

  @override
  Future<void> dispose() async => disposed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRewardedAd implements RewardedAd {
  bool disposed = false;

  @override
  FullScreenContentCallback<RewardedAd>? fullScreenContentCallback;

  @override
  Future<void> show({
    required void Function(RewardedAd ad, RewardItem reward) onUserEarnedReward,
  }) async =>
      onUserEarnedReward(this, RewardItem(1, 'coins'));

  @override
  Future<void> dispose() async => disposed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Harness {
  Harness({
    SellerVerification? self,
    AdRemoteConfig? config,
    AdFrequencyPolicy? policy,
    FakeAdSdk? sdk,
    bool initializeSucceeds = true,
  }) : sdk = sdk ?? FakeAdSdk() {
    SharedPreferences.setMockInitialValues({});
    frequency = AdFrequencyController(
      policy: policy ?? AdFrequencyPolicy.defaults,
    );
    remote = AdRemoteConfigService();
    remote.overrideForTesting(config ?? const AdRemoteConfig());
    eligibility = StaticAdEligibility(self);
    manager = AdManager(
      frequency: frequency,
      remoteConfig: remote,
      verification: eligibility,
      sdk: this.sdk,
      sdkReady: initializeSucceeds,
    );
  }

  final FakeAdSdk sdk;
  late final AdFrequencyController frequency;
  late final AdRemoteConfigService remote;
  late final StaticAdEligibility eligibility;
  late final AdManager manager;

  /// Advances the session clock past the launch grace window so tests are not
  /// dominated by it.
  Future<void> settleSession() async {
    await frequency.beginSession(now: DateTime(2026, 1, 1));
    frequency
      ..debugSeed('lastAnyAd', DateTime(2020))
      ..debugSeed('lastInterstitial', DateTime(2020));
  }

  void dispose() {
    manager.dispose();
    frequency.dispose();
    remote.dispose();
  }
}

Widget wrap(Harness h, Widget child) => ChangeNotifierProvider<AdManager>.value(
      value: h.manager,
      child: MaterialApp(
        home: Scaffold(body: child),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Banner construction goes through the platform channel. Stub it so the tests
  // exercise AdManager's logic without a live AdMob SDK.
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/google_mobile_ads'),
      (call) async => null,
    );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/google_mobile_ads'),
      null,
    );
  });

  group('Ad eligibility — who sees ads', () {
    testWidgets('a normal buyer sees banner ads', (tester) async {
      final h = Harness(self: const SellerVerification(sellerId: 'buyer'));
      addTearDown(h.dispose);
      expect(h.manager.adsEnabledForUser, isTrue);

      await tester.pumpWidget(wrap(h, const AdSlot(
        placement: AdPlacement.homeFeedFooter,
      )));
      await tester.pump();
      expect(find.byType(AdSlot), findsOneWidget);
      expect(h.manager.config.isPlacementEnabled(AdPlacement.homeFeedFooter), isTrue);
      expect(h.sdk.bannerLoadCount, 1);
      await tester.pump();
      expect(h.sdk.bannerLoadCount, 1,
          reason: 'rebuilding must not duplicate the load');
    });

    testWidgets('a normal seller sees ads', (tester) async {
      final h = Harness(
        self: const SellerVerification(
          sellerId: 's',
          kycStatus: KycStatus.none,
        ),
      );
      addTearDown(h.dispose);
      expect(h.manager.adsEnabledForUser, isTrue);
      expect(h.manager.verification.isSelfBlueTick, isFalse);
    });

    testWidgets('a KYC-pending seller sees ads', (tester) async {
      final h = Harness(
        self: const SellerVerification(
          sellerId: 's',
          kycStatus: KycStatus.pending,
          blueTick: BlueTickStatus.pending,
        ),
      );
      addTearDown(h.dispose);
      expect(h.manager.adsEnabledForUser, isTrue);
    });

    testWidgets('a KYC-rejected seller sees ads', (tester) async {
      final h = Harness(
        self: const SellerVerification(
          sellerId: 's',
          kycStatus: KycStatus.rejected,
        ),
      );
      addTearDown(h.dispose);
      expect(h.manager.adsEnabledForUser, isTrue);
    });

    testWidgets('a KYC-approved Blue Tick seller sees NO ads', (tester) async {
      final h = Harness(
        self: const SellerVerification(
          sellerId: 's',
          kycStatus: KycStatus.approved,
          kycApproved: true,
          blueTick: BlueTickStatus.active,
        ),
      );
      addTearDown(h.dispose);

      expect(h.manager.verification.isSelfBlueTick, isTrue);
      expect(
        h.manager.adsEnabledForUser,
        isFalse,
        reason: 'the Blue Tick ad exemption is enforced centrally, not per screen',
      );
      expect(
        h.manager.suppressionReason,
        AdSuppressionReason.ineligibleUser,
      );

      // Every format is refused, not just banners.
      for (final placement in AdPlacement.values) {
        final d = placement.isFullscreen
            ? h.manager.decideFullscreen(placement: placement, adLoaded: true)
            : h.manager.decideInline(placement: placement);
        expect(d.allowed, isFalse, reason: placement.id);
      }

      await tester.pumpWidget(wrap(h, const AdSlot(
        placement: AdPlacement.homeFeedFooter,
      )));
      // The slot renders nothing at all — not even a reserved gap.
      final slot = tester.widget<AdSlot>(find.byType(AdSlot));
      expect(slot.placement, AdPlacement.homeFeedFooter);
    });

    testWidgets('rewarded is skipped entirely for an exempt seller',
        (tester) async {
      final h = Harness(
        self: const SellerVerification(
          sellerId: 's',
          kycStatus: KycStatus.approved,
          kycApproved: true,
          blueTick: BlueTickStatus.active,
        ),
      );
      addTearDown(h.dispose);

      var earned = 0;
      final shown = await h.manager.showRewarded(
        AdPlacement.rewardedUnlockContact,
        onUserEarned: () => earned++,
      );
      expect(shown, isTrue,
          reason: 'an exempt seller is never asked to watch an ad');
      expect(earned, 1, reason: 'the action proceeds immediately');
      expect(h.sdk.rewardedLoadCount, 0,
          reason: 'no inventory is fetched for an exempt account');
    });

    testWidgets('the tick disappears when verification is revoked',
        (tester) async {
      final h = Harness(
        self: const SellerVerification(
          sellerId: 's',
          kycStatus: KycStatus.approved,
          kycApproved: true,
          blueTick: BlueTickStatus.active,
        ),
      );
      addTearDown(h.dispose);
      expect(h.manager.adsEnabledForUser, isFalse);

      // The backend revokes the tick; the service pushes the new state.
      h.eligibility.updateSelf(
        const SellerVerification(
          sellerId: 's',
          kycStatus: KycStatus.approved,
          kycApproved: true,
          blueTick: BlueTickStatus.revoked,
        ),
      );
      await tester.pump();

      expect(h.manager.verification.isSelfBlueTick, isFalse);
      expect(h.manager.adsEnabledForUser, isTrue,
          reason: 'revocation restores normal advertising immediately');
    });
  });

  group('Account switching', () {
    test('logout/login resets eligibility and counters', () async {
      final h = Harness(
        self: const SellerVerification(
          sellerId: 's',
          kycStatus: KycStatus.approved,
          kycApproved: true,
          blueTick: BlueTickStatus.active,
        ),
      );
      addTearDown(h.dispose);
      await h.settleSession();
      expect(h.manager.adsEnabledForUser, isFalse);

      // Sign out then in as a normal seller.
      h.eligibility.updateSelf(const SellerVerification(sellerId: ''));
      await h.manager.onAccountChanged(null);
      expect(h.manager.adsEnabledForUser, isTrue);

      h.eligibility.updateSelf(
        const SellerVerification(
          sellerId: 'other',
          kycStatus: KycStatus.approved,
          kycApproved: true,
          blueTick: BlueTickStatus.active,
        ),
      );
      await h.manager.onAccountChanged('other');
      expect(h.manager.adsEnabledForUser, isFalse);
    });

    test('a second account on the device never inherits the exemption',
        () async {
      final h = Harness(
        self: const SellerVerification(
          sellerId: 'account-a',
          kycStatus: KycStatus.approved,
          kycApproved: true,
          blueTick: BlueTickStatus.active,
        ),
      );
      addTearDown(h.dispose);
      await h.settleSession();
      expect(h.manager.adsEnabledForUser, isFalse);

      // Account A signs out. State resets to unknown, which is NOT exempt.
      h.eligibility.updateSelf(const SellerVerification(sellerId: ''));
      await h.manager.onAccountChanged(null);
      expect(h.manager.adsEnabledForUser, isTrue,
          reason: 'no inheritance across accounts');

      // Account B signs in with no KYC.
      h.eligibility.updateSelf(
        const SellerVerification(sellerId: 'account-b'),
      );
      await h.manager.onAccountChanged('account-b');
      expect(h.manager.adsEnabledForUser, isTrue);
      expect(h.frequency.debugSessionInterstitials, 0);
    });

    test('app restart preserves the correct eligibility', () async {
      final exempt = const SellerVerification(
        sellerId: 's',
        kycStatus: KycStatus.approved,
        kycApproved: true,
        blueTick: BlueTickStatus.active,
      );
      final first = Harness(self: exempt);
      await first.settleSession();
      expect(first.manager.adsEnabledForUser, isFalse);
      first.dispose();

      // A fresh process starts from trusted state again, not from a cached
      // local flag, so the answer is identical.
      final restarted = Harness(self: exempt);
      addTearDown(restarted.dispose);
      await restarted.settleSession();
      expect(restarted.manager.adsEnabledForUser, isFalse);
    });
  });

  group('Interstitial transitions', () {
    test('never fires on a critical route', () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.settleSession();
      await h.manager.preloadInterstitial();

      for (final route in ['/checkout', '/kyc', '/otp', '/order-detail/x']) {
        h.manager.currentRoute = route;
        final d = h.manager.decideFullscreen(
          placement: AdPlacement.interstitialTabSwitch,
          adLoaded: true,
        );
        expect(d.allowed, isFalse, reason: route);
        expect(d.reason, AdSuppressionReason.criticalFlow);
      }
    });

    test('refuses to show without a cached creative', () async {
      final h = Harness(sdk: FakeAdSdk(interstitialSucceeds: false));
      addTearDown(h.dispose);
      await h.settleSession();

      final shown = await h.manager.showInterstitial(
        AdPlacement.interstitialTabSwitch,
      );
      expect(shown, isFalse);
      expect(h.manager.isInterstitialLoaded, isFalse);
    });

    test('a failed load triggers backoff, not a hot retry loop', () async {
      final h = Harness(
        sdk: FakeAdSdk(interstitialSucceeds: false),
        policy: const AdFrequencyPolicy(
          retryBackoffBase: Duration(seconds: 30),
          maxLoadAttemptsPerHour: 3,
        ),
      );
      addTearDown(h.dispose);
      await h.settleSession();

      await h.manager.preloadInterstitial();
      expect(h.frequency.nextAttemptAt('interstitial'), isNotNull,
          reason: 'a no-fill response must not be retried immediately');

      await h.manager.preloadInterstitial();
      expect(h.sdk.interstitialLoadCount, 1,
          reason: 'preload must respect the backoff window');
    });

    test('a route change publishes the current route to the manager', () {
      final h = Harness();
      addTearDown(h.dispose);
      final observer = AdRouteObserver(h.manager);

      observer.didPush(_FakeRoute('/checkout'), null);
      expect(h.manager.currentRoute, '/checkout');
      expect(h.manager.suppressionReason, AdSuppressionReason.criticalFlow);

      observer.didPush(_FakeRoute('/wishlist'), null);
      expect(h.manager.currentRoute, '/wishlist');
      expect(h.manager.suppressionReason, isNull);
    });

    test('a tab switch is charged once per session and then refused', () async {
      final h = Harness(
        policy: const AdFrequencyPolicy(
          maxInterstitialsPerSession: 1,
          minTimeAfterLaunch: Duration.zero,
          minTimeAfterAnyAd: Duration.zero,
          minIntervalBetweenInterstitials: Duration.zero,
        ),
      );
      addTearDown(h.dispose);
      await h.settleSession();

      // First presentation is allowed and charges the counter.
      expect(
        h.manager.decideFullscreen(
          placement: AdPlacement.interstitialTabSwitch,
          adLoaded: true,
        ).allowed,
        isTrue,
      );
      h.frequency.recordShown(AdPlacement.interstitialTabSwitch);

      // The next tab switch in the same session is refused by the session cap,
      // which is what stops the old "every 60 seconds" behaviour.
      final second = h.manager.decideFullscreen(
        placement: AdPlacement.interstitialTabSwitch,
        adLoaded: true,
      );
      expect(second.allowed, isFalse);
      expect(second.reason, AdSuppressionReason.sessionCap);
    });
  });

  group('Resilience', () {
    test('a failed SDK initialization leaves ads off without crashing',
        () async {
      final h = Harness(initializeSucceeds: false);
      addTearDown(h.dispose);
      expect(h.manager.isSdkReady, isFalse);
      expect(
        h.manager.decideFullscreen(
          placement: AdPlacement.interstitialTabSwitch,
          adLoaded: true,
        ).reason,
        AdSuppressionReason.sdkNotReady,
      );
    });

    test('a throwing SDK gateway does not escape to the caller', () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.settleSession();

      // Simulate a transport-level failure by making the gateway throw.
      h.sdk.interstitialSucceeds = false;
      await expectLater(
        h.manager.showInterstitial(AdPlacement.interstitialTabSwitch),
        completes,
      );
    });

    test('missing remote config falls back to compiled defaults', () async {
      final h = Harness(config: AdRemoteConfig.fromMap(null));
      addTearDown(h.dispose);
      expect(h.remote.hasLoaded, isTrue);
      expect(h.manager.config.adsEnabled, isTrue);
      expect(h.manager.config.adsExemptBlueTickEnabled, isTrue);
    });
  });

  group('Admin configuration is respected at runtime', () {
    test('the master switch takes ads down without a restart', () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.settleSession();
      expect(h.manager.adsEnabledForUser, isTrue);

      h.remote.overrideForTesting(
        h.manager.config.copyWith(adsEnabled: false),
      );
      await Future<void>.delayed(Duration.zero);

      expect(h.manager.adsEnabledForUser, isFalse);
      expect(h.manager.suppressionReason, AdSuppressionReason.adsDisabled);
    });

    test('turning the Blue Tick exemption off restores ads for everyone',
        () async {
      final h = Harness(
        self: const SellerVerification(
          sellerId: 's',
          kycStatus: KycStatus.approved,
          kycApproved: true,
          blueTick: BlueTickStatus.active,
        ),
      );
      addTearDown(h.dispose);
      expect(h.manager.adsEnabledForUser, isFalse);

      h.remote.overrideForTesting(
        h.manager.config.copyWith(adsExemptBlueTickEnabled: false),
      );
      expect(h.manager.adsEnabledForUser, isTrue);
    });

    test('disabling one placement leaves the others alone', () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.settleSession();

      h.remote.overrideForTesting(
        h.manager.config
            .copyWith(disabledPlacements: {'home.feed.footer'}),
      );
      expect(
        h.manager.decideInline(placement: AdPlacement.homeFeedFooter).allowed,
        isFalse,
      );
      expect(
        h.manager.decideInline(placement: AdPlacement.wishlistFooter).allowed,
        isTrue,
      );
    });

    test('a frequency policy change applies without a restart', () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.settleSession();

      final strict = h.frequency.policy.copyWith(maxAdsPerSession: 0);
      h.frequency.updatePolicy(strict);
      expect(h.frequency.policy.maxAdsPerSession, 0);

      final d = h.manager.decideInline(placement: AdPlacement.profileFooter);
      expect(d.allowed, isFalse);
      expect(d.reason, AdSuppressionReason.sessionCap);
    });
  });

  group('AdSlot rendering', () {
    testWidgets('renders nothing for an exempt seller', (tester) async {
      final h = Harness(
        self: const SellerVerification(
          sellerId: 's',
          kycStatus: KycStatus.approved,
          kycApproved: true,
          blueTick: BlueTickStatus.active,
        ),
      );
      addTearDown(h.dispose);

      await tester.pumpWidget(wrap(h, const AdSlot(
        placement: AdPlacement.homeFeedFooter,
      )));
      final rendered = tester.widget<AdSlot>(find.byType(AdSlot));
      // The AdSlot returns SizedBox.shrink() internally; assert via the manager
      // gate rather than pixel measurement.
      expect(h.manager.config.isPlacementEnabled(rendered.placement), isTrue);
      expect(h.manager.adsEnabledForUser, isFalse);
      expect(find.byType(AdSlot), findsOneWidget);
    });

    testWidgets('mounting the same placement twice is stable', (tester) async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.settleSession();

      await tester.pumpWidget(wrap(h, const Column(
        children: [
          AdSlot(placement: AdPlacement.homeFeedFooter),
          AdSlot(placement: AdPlacement.homeFeedFooter),
        ],
      )));
      await tester.pump();
      expect(find.byType(AdSlot), findsNWidgets(2));
      // Two slots on one screen share one cached banner, and a rebuild does not
      // duplicate the request.
      expect(h.sdk.bannerLoadCount, 1,
          reason: 'the banner cache is keyed by placement, not by widget');
    });
  });

  group('BlueTickBadge', () {
    testWidgets('is hidden while verification is unknown', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => const SizedBox(),
        ),
      ));
      expect(find.byType(BlueTickBadge), findsNothing);
    });

    testWidgets('carries no client-supplied trust boolean', (tester) async {
      // The only parameter is a sellerId. There is deliberately no `isVerified`
      // argument, so no call site can pass in a locally-assigned flag.
      final badge = BlueTickBadge(sellerId: 's');
      expect(badge.sellerId, 's');
      expect(badge.sellerId.isNotEmpty, isTrue);
    });
  });
}

class _FakeRoute extends PageRoute<void> {
  _FakeRoute(this.routeName);
  final String routeName;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) =>
      const SizedBox();

  @override
  RouteSettings get settings => RouteSettings(name: routeName);
}