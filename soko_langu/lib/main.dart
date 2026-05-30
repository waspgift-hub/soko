import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:go_router/go_router.dart';
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
import 'app/router.dart' as router_lib;
import 'app/app_state.dart' as app_state;

final NotificationService notificationService = NotificationService();
final LocalizationService localizationService = LocalizationService();
final InterstitialAdService interstitialAdService = InterstitialAdService();
final ThemeManager themeManager = ThemeManager();
final GoRouter appRouter = router_lib.buildRouter();

typedef LangCallback = void Function(String);
typedef CurrencyCallback = void Function(String);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
    );
  } catch (e) {
    debugPrint('Firebase: initialization failed — $e');
  }

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

  try {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: const AndroidPlayIntegrityProvider(),
    );
  } catch (e) {
    debugPrint('AppCheck: failed — $e');
  }
  try {
    await MobileAds.instance.initialize();
    debugPrint('AdMob: initialized successfully');
  } catch (e) {
    debugPrint('AdMob: initialization failed — $e');
  }
  try {
    await GoogleSignIn.instance.initialize();
  } catch (e) {
    debugPrint('GoogleSignIn: failed — $e');
  }
  await SecurityService().initialize();
  await themeManager.load();
  final prefs = await SharedPreferences.getInstance();
  app_state.onboardingSeen = prefs.getBool('onboarding_seen') ?? false;
  try {
    await NotificationService.initLocalNotifications();
  } catch (e) {
    debugPrint('LocalNotifications: failed — $e');
  }
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
    final curSym = LocalizationService.supportedCurrencies['TZS']?['symbol'] ?? 'TSh';
    final message = 'Habari, nimeona bidhaa "$productName" ikiwa $curSym ${newPrice.toStringAsFixed(0)}. Naomba kununua.';
    WhatsAppService().openWhatsApp(
      phoneNumber: phone,
      message: message,
    );
  };
  try { notificationService.initialize(); } catch (e) { debugPrint('notificationService: $e'); }

  await ExchangeRateService().initialize();
  AiService.initialize(GroqService());

  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.sokolangu.audio.playback',
      androidNotificationChannelName: 'Soko Langu Music',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: false,
      notificationColor: const Color(0xFF2D6A4F),
      androidNotificationIcon: 'mipmap/ic_launcher',
      androidNotificationClickStartsActivity: true,
    );
  } catch (e) {
    debugPrint('JustAudioBackground init: failed — $e');
  }

  runApp(const SokoLanguApp());
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

  static AppConfig of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppConfig>()!;
  }

  @override
  bool updateShouldNotify(AppConfig old) =>
      langCode != old.langCode || currencyCode != old.currencyCode;
}

class SokoLanguApp extends StatefulWidget {
  const SokoLanguApp({super.key});

  @override
  State<SokoLanguApp> createState() => _SokoLanguAppState();
}

class _SokoLanguAppState extends State<SokoLanguApp> {
  String _langCode = 'en';
  String _currencyCode = 'TZS';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    themeManager.addListener(_onThemeChange);
  }

  @override
  void dispose() {
    themeManager.removeListener(_onThemeChange);
    super.dispose();
  }

  void _onThemeChange() {
    if (mounted) setState(() {});
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _langCode = prefs.getString('language_code') ?? 'en';
      _currencyCode = prefs.getString('currency') ?? 'TZS';
    });
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

    return MaterialApp.router(
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
      title: 'Soko Langu',
      theme: themeManager.lightTheme,
      darkTheme: themeManager.darkTheme,
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) {
        Responsive.init(context);
        Widget content = SafeArea(child: child!);
        if (isDark) {
          content = Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF000000), Color(0xFF001A0A)],
              ),
            ),
            child: content,
          );
        } else {
          content = Container(
            color: Theme.of(context).colorScheme.surface,
            child: content,
          );
        }
        return AppConfig(
          langCode: _langCode,
          currencyCode: _currencyCode,
          onSetLanguage: _setLanguage,
          onSetCurrency: _setCurrency,
          child: content,
        );
      },
    );
  }
}
