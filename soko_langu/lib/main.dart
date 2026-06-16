import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:go_router/go_router.dart';
import 'package:audio_service/audio_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';
import 'services/localization_service.dart';
import 'services/interstitial_ad_service.dart';
import 'services/security_service.dart';
import 'services/whatsapp_service.dart';
import 'services/ai/ai_service.dart';
import 'services/groq_service.dart';
import 'services/exchange_rate_service.dart';
import 'theme/theme_manager.dart';
import 'utils/responsive.dart';
import 'widgets/google_loading.dart';
import 'widgets/audio_fab.dart';
import 'widgets/offline_banner.dart';
import 'app/router.dart' as router_lib;
import 'app/app_state.dart' as app_state;
import 'services/audio_handler.dart';

final NotificationService notificationService = NotificationService();
final LocalizationService localizationService = LocalizationService();
final InterstitialAdService interstitialAdService = InterstitialAdService();
final ThemeManager themeManager = ThemeManager();
final GoRouter appRouter = router_lib.buildRouter();

typedef LangCallback = void Function(String);
typedef CurrencyCallback = void Function(String);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Only Firebase is critical for the app to function — init everything else
  // in the background after the first frame renders
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
    );
  } catch (e) {
    debugPrint('Firebase: initialization failed — $e');
  }

  runApp(const SokoVibeApp());
}

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

  static AppConfig? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppConfig>();
  }

  static AppConfig of(BuildContext context) {
    return maybeOf(context) ??
        (throw FlutterError(
          'AppConfig.of() was called with a context that does not contain an AppConfig widget.\n'
          'This can happen when the context used is not a descendant of SokoVibeApp.\n'
          'Make sure AppConfig is placed above the widget that calls AppConfig.of(context).',
        ));
  }

  @override
  bool updateShouldNotify(AppConfig old) =>
      langCode != old.langCode || currencyCode != old.currencyCode;
}

class SokoVibeApp extends StatefulWidget {
  const SokoVibeApp({super.key});

  @override
  State<SokoVibeApp> createState() => _SokoVibeAppState();
}

class _SokoVibeAppState extends State<SokoVibeApp>
    with WidgetsBindingObserver {
  String _langCode = 'en';
  String _currencyCode = 'TZS';
  bool _appReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    themeManager.addListener(_onThemeChange);
    _initApp();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    themeManager.removeListener(_onThemeChange);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _appReady) {
      setState(() {});
    }
  }

  void _onThemeChange() {
    if (mounted) setState(() {});
  }

  Future<void> _initApp() async {
    // Phase 1 — Fast local init (SharedPreferences, theme)
    await themeManager.load();
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    app_state.onboardingSeen = prefs.getBool('onboarding_seen') ?? false;
    setState(() {
      _langCode = prefs.getString('language_code') ?? 'en';
      _currencyCode = prefs.getString('currency') ?? 'TZS';
      _appReady = true;
    });
    _setupNotificationCallbacks();

    // Phase 2 — Heavy background init (fire-and-forget, doesn't block UI)
    _initBackgroundServices(prefs);
  }

  void _setupNotificationCallbacks() {
    NotificationService.onNotificationTap = (data) {
      final type = data['type'] as String?;
      if (type == 'order' || type == 'boost') {
        appRouter.push('/notifications');
      } else if (type == 'flash_sale') {
        appRouter.push('/flash-sale');
      } else if (type == 'product') {
        final productId = data['productId'] as String?;
        if (productId != null) {
          appRouter.push('/product/$productId');
        }
      }
    };

    NotificationService.onPriceDropTap = (data) {
      final phone = data['sellerPhone'] as String? ?? '';
      final productName = data['productName'] as String? ?? '';
      final newPrice = data['newPrice'] as num? ?? 0;
      if (phone.isEmpty) return;
      final curSym =
          LocalizationService.supportedCurrencies['TZS']?['symbol'] ?? 'TSh';
      final message = LocalizationService.translate('price_drop_whatsapp', 'sw')
          .replaceAll('{0}', productName)
          .replaceAll('{1}', curSym)
          .replaceAll('{2}', newPrice.toStringAsFixed(0));
      WhatsAppService().openWhatsApp(phoneNumber: phone, message: message);
    };
  }

  Future<void> _initBackgroundServices(SharedPreferences prefs) async {
    // Crashlytics
    try {
      FlutterError.onError = (details) {
        FirebaseCrashlytics.instance.recordFlutterFatalError(details);
      };
      ui.PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
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
          providerAndroid: const AndroidPlayIntegrityProvider(),
          providerApple: const AppleDeviceCheckProvider(),
        );
      } catch (e) {
        debugPrint('AppCheck: failed — $e');
      }
      // AdMob
      try {
        await MobileAds.instance.initialize();
      } catch (e) {
        debugPrint('AdMob: failed — $e');
      }
      // Security
      try {
        await SecurityService().initialize();
      } catch (e) {
        debugPrint('SecurityService: failed — $e');
      }
      // Local notifications
      try {
        await NotificationService.initLocalNotifications();
      } catch (e) {
        debugPrint('AwesomeNotifications init: $e');
      }
    }

    try {
      await GoogleSignIn.instance.initialize();
    } catch (e) {
      debugPrint('GoogleSignIn: failed — $e');
    }

    try {
      await notificationService.initialize();
    } catch (e) {
      debugPrint('notificationService: $e');
    }

    try {
      await ExchangeRateService().initialize();
    } catch (e) {
      debugPrint('ExchangeRateService: failed — $e');
    }

    AiService.initialize(GroqService());

    if (!kIsWeb) {
      try {
        // Request notification permission for Android 13+
        await Permission.notification.request();

        final audioHandler = SokoAudioHandler();
        await AudioService.init(
          builder: () => audioHandler,
          config: const AudioServiceConfig(
            androidNotificationChannelId: 'com.soko_vibe.music',
            androidNotificationChannelName: 'Soko Vibe Music',
            androidNotificationChannelDescription:
                'Audio playback controls for Soko Vibe',
            androidNotificationIcon: 'ic_notification',

            notificationColor: Color(0xFF40916C),
            androidStopForegroundOnPause: false,
            androidNotificationClickStartsActivity: true,
            androidResumeOnClick: true,
            androidNotificationOngoing: true,
          ),
        );
        debugPrint('AudioService.init: SUCCESS');
        final notifStatus = await Permission.notification.status;
        debugPrint('Notification permission status: $notifStatus');
      } catch (e) {
        debugPrint('AudioService init failed: $e');
      }
    }
  }

  void _setLanguage(String code) {
    setState(() => _langCode = code);
  }

  void _setCurrency(String code) {
    setState(() => _currencyCode = code);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeManager.isDark;

    if (!_appReady) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: themeManager.lightTheme,
        darkTheme: themeManager.darkTheme,
        themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
        home: const Scaffold(body: GoogleLoadingPage()),
      );
    }

    return MaterialApp.router(
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
      title: 'Soko Vibe',
      theme: themeManager.lightTheme,
      darkTheme: themeManager.darkTheme,
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) {
        Responsive.init(context);
        Widget content = child!;
        final cs = Theme.of(context).colorScheme;

        if (kIsWeb && Responsive.isDesktop) {
          content = Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: content,
            ),
          );
        }

        if (isDark) {
          content = Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  cs.surface,
                  cs.surfaceContainerHighest.withValues(alpha: 0.3),
                ],
              ),
            ),
            child: content,
          );
        } else {
          content = Container(color: cs.surface, child: content);
        }
        content = OfflineBanner(child: content);
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
                ],
              ),
              const AudioFab(),
            ],
          ),
        );
      },
    );
  }
}
