import 'dart:async';
import 'dart:ui' as ui;

import 'package:audio_service/audio_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
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
import 'providers/music_state_notifier.dart';
import 'providers/product_feed_provider.dart';
import 'repositories/auth_repository.dart';
import 'services/ai/ai_service.dart';
import 'services/app_lock_service.dart';
import 'services/audio_cache_service.dart';
import 'services/audio_handler.dart';
import 'widgets/mini_player.dart';
import 'services/auth_service.dart';
import 'services/exchange_rate_service.dart';
import 'services/onboarding_service.dart';
import 'services/magic_link_service.dart';
import 'services/groq_service.dart';
import 'services/interstitial_ad_service.dart';
import 'services/localization_service.dart';
import 'services/local_cache_service.dart';
import 'services/notification_service.dart';
import 'services/security_service.dart';
import 'theme/theme_manager.dart';
import 'utils/responsive.dart';
import 'widgets/app_lock_overlay.dart';
import 'widgets/maintenance_gate.dart';
import 'widgets/connectivity_wrapper.dart';

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
    try {
      await AudioCacheService().init();
    } catch (e) {
      debugPrint('AudioCacheService: init failed — $e');
    }
  }

  // --- Global error handlers (must be set before runApp to catch startup crashes) ---
  _setupGlobalErrorHandlers();

  // --- FCM background handler registration ---
  // SAFE: only stores a callback reference; the handler itself calls Firebase.initializeApp.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // --- AudioService: init before runApp on non-web, so the handler
  // Completer resolves before the first widget tree is built. This
  // eliminates the retry loop that MusicStateNotifier previously needed.
  if (!kIsWeb) {
    await _initAudioService();
  }

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

/// Initialize AudioService before the first frame.
///
/// Must run before [runApp] so [musicHandlerFuture] resolves before any
/// widget (e.g. [MiniPlayer], [PlayerScreen]) tries to read playback state.
Future<void> _initAudioService() async {
  try {
    await AudioService.init(
      builder: () {
        final handler = MusicHandler();
        bindMusicHandler(handler);
        return handler;
      },
      config: AudioServiceConfig(
        androidNotificationChannelId: 'com.soko_vibe.music',
        androidNotificationChannelName: 'Soko Vibe Music',
        androidNotificationChannelDescription:
            'Audio playback controls for Soko Vibe',
        androidNotificationIcon: 'ic_notification',
        notificationColor: Color(0xFF40916C),
        androidStopForegroundOnPause: false,
        androidNotificationOngoing: true,
        androidNotificationClickStartsActivity: true,
        androidResumeOnClick: true,
        androidShowNotificationBadge: true,
        preloadArtwork: true,
      ),
    );
  } catch (e) {
    debugPrint('AudioService init failed: $e');
  }
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

class _SokoVibeAppState extends State<SokoVibeApp>
    with WidgetsBindingObserver {
  String _langCode = 'en';
  String _currencyCode = 'TZS';
  late final ProductFeedProvider _productFeedProvider;
  late final MusicStateNotifier _musicState;
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
    _musicState = MusicStateNotifier();
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      AppLockService.instance.onBackground();
    } else if (state == AppLifecycleState.resumed) {
      AppLockService.instance.onResume();
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
    // Load theme asynchronously (UI already has valid defaults)
    themeManager.load();

    try {
      final prefs = await SharedPreferences.getInstance();

      setState(() {
        _langCode = prefs.getString('language_code') ?? 'en';
        _currencyCode = prefs.getString('currency') ?? 'TZS';
      });

      await _authNotifier.initialize();
      app_state.appStateNotifier.setAppInitialized();

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

      // Start MusicStateNotifier streams (handler already ready since
      // AudioService.init completed before runApp).
      _musicState.init();
    } catch (e) {
      debugPrint('_initApp: error — $e');
    }
  }

  // -----------------------------------------------------------------------
  // Notification tap callbacks
  // -----------------------------------------------------------------------

  void _setupNotificationCallbacks() {
    NotificationService.onNotificationTap = (Map<String, dynamic> data) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final type = data['type'] as String?;
        switch (type) {
          case 'order':
          case 'boost':
            appRouter.push('/notifications');
          case 'flash_sale':
            appRouter.push('/flash-sale');
          case 'product':
            final productId = data['productId'] as String?;
            if (productId != null) {
              appRouter.push('/product/$productId');
            }
        }
      });
    };

    NotificationService.onPaymentNotificationTap =
        (Map<String, dynamic> data) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final orderId = (data['orderId'] ?? data['transactionId']) as String?;
        if (orderId != null) {
          appRouter.push('/receipt/$orderId');
        }
      });
    };
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
        ChangeNotifierProvider.value(value: _musicState),
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
    final cs = Theme.of(context).colorScheme;

    // Web desktop constraint
    if (kIsWeb && Responsive.isDesktop) {
      content = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: content,
        ),
      );
    }

    // Cosmic Slate gradient background
    final isDark = Theme.of(context).brightness == Brightness.dark;
    content = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [
                  cs.surface.withValues(alpha: 0.97),
                  cs.surfaceContainerLow,
                  cs.surface.withValues(alpha: 0.97),
                ]
              : [
                  cs.surface.withValues(alpha: 0.95),
                  cs.surfaceContainerLow,
                  cs.surface.withValues(alpha: 0.95),
                ],
        ),
      ),
      child: content,
    );

    // Cross-cutting overlays
    content = ConnectivityWrapper(child: content);
    content = MaintenanceGate(child: content);
    content = AppLockOverlay(child: content);

    return AppConfig(
      langCode: _langCode,
      currencyCode: _currencyCode,
      onSetLanguage: _setLanguage,
      onSetCurrency: _setCurrency,
      child: Stack(
        children: [
          Column(
            children: [
              Expanded(child: content),
              const MiniPlayer(),
            ],
          ),
        ],
      ),
    );
  }
}
