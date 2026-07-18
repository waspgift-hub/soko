import 'dart:async';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// --- App modules ---
import 'app/app_state.dart' as app_state;
import 'app/router.dart' as router_lib;
import 'firebase_messaging_background.dart';
import 'firebase_options.dart';
import 'notifiers/auth_notifier.dart';
import 'providers/product_feed_provider.dart';
import 'repositories/auth_repository.dart';
import 'services/ai/ai_service.dart';
import 'services/app_lock_service.dart';
import 'services/auth_service.dart';
import 'services/exchange_rate_service.dart';
import 'services/onboarding_service.dart';
import 'services/magic_link_service.dart';
import 'services/groq_service.dart';
import 'services/localization_service.dart';
import 'services/local_cache_service.dart';
import 'services/notification_service.dart';
import 'services/interstitial_ad_service.dart';
import 'services/analytics_service.dart';
import 'services/security_service.dart';
import 'theme/theme_manager.dart';
import 'utils/responsive.dart';
import 'widgets/app_lock_overlay.dart';
import 'widgets/maintenance_gate.dart';
import 'widgets/connectivity_wrapper.dart';
import 'widgets/transaction_status_watcher.dart';
import 'widgets/age_gate_dialog.dart';
import 'widgets/premium_background.dart';
import 'widgets/in_app_notification_overlay.dart';

// ---------------------------------------------------------------------------
// Global singletons — scoped to app lifetime, lazily resolved where possible.
// ---------------------------------------------------------------------------

final NotificationService notificationService = NotificationService();
final LocalizationService localizationService = LocalizationService();
final SecurityService securityService = SecurityService();
final InterstitialAdService interstitialAdService = InterstitialAdService();
final ThemeManager themeManager = ThemeManager();
final GoRouter appRouter = router_lib.buildRouter();

typedef LangCallback = void Function(String);
typedef CurrencyCallback = void Function(String);

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // --- Firebase initialization (blocking — required before any Firestore call) ---
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    if (!kIsWeb) {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
      );
    }
  } catch (e) {
    debugPrint('Firebase: initialization failed — $e');
  }

  // --- Local cache (Hive) — must be ready before any repository reads ---
  if (!kIsWeb) {
    try {
      await LocalCacheService.init();
    } catch (e) {
      debugPrint('LocalCacheService: init failed — $e');
    }
  }

  // --- Global error handlers (must be set before runApp to catch startup crashes) ---
  _setupGlobalErrorHandlers();

  // --- Google Sign-In: initialize before any sign in calls ---
  if (!kIsWeb) {
    try {
      await GoogleSignIn.instance.initialize();
    } catch (e) {
      debugPrint('GoogleSignIn: init failed — $e');
    }
  }

  // --- FCM background handler registration ---
  // SAFE: only stores a callback reference; the handler itself calls Firebase.initializeApp.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  runApp(const SokoVibeApp());
}

/// Registers Crashlytics as the top-level error handler.
/// Called before [runApp] so every error (including startup-phase) is captured.
void _setupGlobalErrorHandlers() {
  FlutterError.onError = (FlutterErrorDetails details) {
    FirebaseCrashlytics.instance.recordFlutterFatalError(details);
  };

  ui.PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true; // Prevent the isolate from crashing after reporting
  };
}

// ---------------------------------------------------------------------------
// AppConfig — InheritedWidget for language / currency propagation
// ---------------------------------------------------------------------------

class AppConfig extends InheritedWidget {
  final String langCode;
  final String currencyCode;
  final LangCallback onSetLanguage;
  final CurrencyCallback onSetCurrency;

  const AppConfig({
    super.key,
    required this.langCode,
    required this.currencyCode,
    required this.onSetLanguage,
    required this.onSetCurrency,
    required super.child,
  });

  static AppConfig? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppConfig>();

  static AppConfig of(BuildContext context) {
    return maybeOf(context) ??
        (throw FlutterError(
          'AppConfig not found — ensure AppConfig is an ancestor of the calling widget.\n'
          'This usually means AppConfig.of() was called too early or from a different widget tree.',
        ));
  }

  @override
  bool updateShouldNotify(AppConfig old) =>
      langCode != old.langCode || currencyCode != old.currencyCode;
}

// ---------------------------------------------------------------------------
// Root widget
// ---------------------------------------------------------------------------

class SokoVibeApp extends StatefulWidget {
  const SokoVibeApp({super.key});

  @override
  State<SokoVibeApp> createState() => _SokoVibeAppState();
}

class _SokoVibeAppState extends State<SokoVibeApp> with WidgetsBindingObserver {
  String _langCode = 'en';
  String _currencyCode = 'TZS';
  late final ProductFeedProvider _productFeedProvider;
  late final AuthRepository _authRepository;
  late final OnboardingService _onboardingService;
  late final AuthNotifier _authNotifier;
  MagicLinkService? _magicLinkService;

  // -----------------------------------------------------------------------
  // Lifecycle
  // -----------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _productFeedProvider = ProductFeedProvider();
    _authRepository = AuthRepository();
    _onboardingService = OnboardingService();
    _authNotifier = AuthNotifier(
      authRepo: _authRepository,
      onboardingService: _onboardingService,
    );
    WidgetsBinding.instance.addObserver(this);
    themeManager.addListener(_onThemeChange);
    _initApp();
  }

  @override
  void dispose() {
    _magicLinkService?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    themeManager.removeListener(_onThemeChange);
    _productFeedProvider.dispose();
    super.dispose();
  }

  // -----------------------------------------------------------------------
  // App lifecycle observer
  // -----------------------------------------------------------------------

  Timer? _sessionTimer;
  final _analyticsService = AnalyticsService();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      AppLockService.instance.onBackground();
      _sessionTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      AppLockService.instance.onResume();
      _trackSession();
    }
  }

  void _trackSession() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _analyticsService.trackUserSession(uid);
      _sessionTimer?.cancel();
      _sessionTimer = Timer.periodic(const Duration(minutes: 5), (_) {
        _analyticsService.trackUserSession(uid);
      });
    }
  }

  // -----------------------------------------------------------------------
  // Theme change listener — triggers widget rebuild
  // -----------------------------------------------------------------------

  void _onThemeChange() {
    if (mounted) setState(() {});
  }

  // -----------------------------------------------------------------------
  // App initialization
  // -----------------------------------------------------------------------

  /// Loads theme and preferences, then fires background services.
  Future<void> _initApp() async {
    // Load theme (reads saved preference from SharedPreferences)
    await themeManager.load();

    try {
      final prefs = await SharedPreferences.getInstance();

      setState(() {
        _langCode = prefs.getString('language_code') ?? 'en';
        _currencyCode = prefs.getString('currency') ?? 'TZS';
      });

      await _authNotifier.initialize();
      app_state.appStateNotifier.setAppInitialized();
      _trackSession();

      _magicLinkService = MagicLinkService(_authNotifier);
      unawaited(_magicLinkService!.initialize());

      // Sync phone from onboarding to Firestore if user is logged in
      final phone = prefs.getString('phone_number');
      if (phone != null && phone.isNotEmpty) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null && !(prefs.getBool('phone_synced') ?? false)) {
          AuthService().syncPhoneOnProfile(user.uid, phone);
          await prefs.setBool('phone_synced', true);
        }
      }

      // Load PIN lock state
      await AppLockService.instance.load();

      _setupNotificationCallbacks();

      // Background services (fire-and-forget)
      _initBackgroundServices(prefs);
    } catch (e) {
      debugPrint('_initApp: error — $e');
    }
  }

  // -----------------------------------------------------------------------
  // Notification tap callbacks
  // -----------------------------------------------------------------------

  void _setupNotificationCallbacks() {
    NotificationService.onForegroundMessage = (title, body, type, data) {
      final ctx = router_lib.rootNavigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        InAppNotificationOverlay.show(
          context: ctx,
          title: title,
          body: body,
          type: type,
          data: data,
          onTap: () => _onNotificationTap(type, data, ctx),
        );
      }
    };

    NotificationService.onNotificationTap = (Map<String, dynamic> data) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final type = data['type'] as String?;
        _onNotificationTap(type, data, context);
      });
    };

    NotificationService.onPaymentNotificationTap = (Map<String, dynamic> data) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final orderId = (data['orderId'] ?? data['transactionId']) as String?;
        if (orderId != null) {
          _pushIfNotCurrent('/receipt/$orderId', context);
        }
      });
    };
  }

  void _onNotificationTap(
    String? type,
    Map<String, dynamic>? data,
    BuildContext ctx,
  ) {
    switch (type) {
      case 'order':
      case 'boost':
        _pushIfNotCurrent('/notifications', ctx);
      case 'flash_sale':
        _pushIfNotCurrent('/flash-sale', ctx);
      case 'product':
        final productId = data?['productId'] as String?;
        if (productId != null) {
          _pushIfNotCurrent('/product/$productId', ctx);
        }
    }
  }

  void _pushIfNotCurrent(String location, [BuildContext? context]) {
    if (context != null && mounted) {
      final current = GoRouterState.of(context).matchedLocation;
      if (current == location) return;
    }
    appRouter.push(location);
  }

  // -----------------------------------------------------------------------
  // Phase 2 — Background service initialization
  // -----------------------------------------------------------------------

  Future<void> _initBackgroundServices(SharedPreferences prefs) async {
    // Crashlytics
    try {
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
    } catch (e) {
      debugPrint('Crashlytics: failed — $e');
    }

    // Performance
    try {
      await FirebasePerformance.instance.setPerformanceCollectionEnabled(true);
    } catch (e) {
      debugPrint('Performance: failed — $e');
    }

    if (!kIsWeb) {
      // App Check
      try {
        await FirebaseAppCheck.instance.activate(
          providerAndroid: kDebugMode
              ? const AndroidDebugProvider()
              : const AndroidPlayIntegrityProvider(),
          providerApple: const AppleDeviceCheckProvider(),
        );
        if (kDebugMode) {
          final tokenStr = await FirebaseAppCheck.instance.getToken(true);
          debugPrint('🔥 AppCheck Debug Token (register in Firebase Console):');
          debugPrint(tokenStr ?? 'null');
        }
      } catch (e) {
        debugPrint('AppCheck: failed — $e');
      }

      // AdMob
      try {
        await MobileAds.instance.initialize();
      } catch (e) {
        debugPrint('AdMob: failed — $e');
      }

      // Security (root/jailbreak detection)
      try {
        await SecurityService().initialize();
      } catch (e) {
        debugPrint('SecurityService: failed — $e');
      }

      // Awesome Notifications (local channels)
      try {
        await NotificationService.initLocalNotifications();
      } catch (e) {
        debugPrint('AwesomeNotifications init: $e');
      }
    }

    // FCM push + in-app notification service
    try {
      await notificationService.initialize();
    } catch (e) {
      debugPrint('notificationService: $e');
    }

    // Exchange rates (for multi-currency display)
    try {
      await ExchangeRateService().initialize();
    } catch (e) {
      debugPrint('ExchangeRateService: failed — $e');
    }

    // AI assistant
    AiService.initialize(GroqService());
  }

  // -----------------------------------------------------------------------
  // Language / Currency setters
  // -----------------------------------------------------------------------

  void _setLanguage(String code) {
    setState(() => _langCode = code);
  }

  void _setCurrency(String code) {
    setState(() => _currencyCode = code);
  }

  // -----------------------------------------------------------------------
  // Build
  // -----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _productFeedProvider),
        ChangeNotifierProvider.value(value: themeManager),
        Provider.value(value: _authRepository),
        Provider.value(value: _onboardingService),
        ChangeNotifierProvider.value(value: _authNotifier),
      ],
      child: MaterialApp.router(
        routerConfig: appRouter,
        debugShowCheckedModeBanner: false,
        title: 'Soko Vibe',
        theme: themeManager.lightTheme,
        darkTheme: themeManager.darkTheme,
        themeMode: themeManager.isDark ? ThemeMode.dark : ThemeMode.light,
        builder: _appBuilder,
      ),
    );
  }

  /// Extracted builder — keeps [build] clean and allows the closure to be
  /// reused without unnecessary allocations.
  Widget _appBuilder(BuildContext context, Widget? child) {
    Responsive.init(context);
    Widget content = child!;

    // Web desktop constraint
    if (kIsWeb && Responsive.isDesktop) {
      content = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: content,
        ),
      );
    }

    // Premium animated background with floating particles
    content = PremiumBackground(child: content);

    // Cross-cutting overlays
    content = ConnectivityWrapper(child: content);
    content = MaintenanceGate(child: content);
    content = AppLockOverlay(child: content);
    content = TransactionStatusWatcher(child: content);
    content = _AgeGateOverlay(child: content);

    return AppConfig(
      langCode: _langCode,
      currencyCode: _currencyCode,
      onSetLanguage: _setLanguage,
      onSetCurrency: _setCurrency,
      child: Stack(
        children: [
          Column(children: [Expanded(child: content)]),
        ],
      ),
    );
  }
}

/// Shows age gate dialog once on first launch. Does NOT block the app.
class _AgeGateOverlay extends StatefulWidget {
  final Widget child;
  const _AgeGateOverlay({required this.child});

  @override
  State<_AgeGateOverlay> createState() => _AgeGateOverlayState();
}

class _AgeGateOverlayState extends State<_AgeGateOverlay> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('age_gate_confirmed') == true) return;
      await AgeGateDialog.show(context);
      await prefs.setBool('age_gate_confirmed', true);
    } catch (_) {
      // fail-safe — never block the app
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
