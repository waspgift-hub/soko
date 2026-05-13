import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';
import 'services/localization_service.dart';
import 'services/auto_lock_service.dart';
import 'services/presence_service.dart';
import 'services/interstitial_ad_service.dart';
import 'package:audio_service/audio_service.dart';
import 'services/audio_player_service.dart';
import 'screens/auth/auth_gate.dart';
import 'screens/auth/lock_screen.dart';
import 'screens/call/incoming_call_screen.dart';
import 'services/call_service.dart';
import 'services/security_service.dart';
import 'theme/theme_manager.dart';
import 'utils/responsive.dart';

final NotificationService notificationService = NotificationService();
final LocalizationService localizationService = LocalizationService();
final AutoLockService autoLockService = AutoLockService();
final PresenceService presenceService = PresenceService();
final InterstitialAdService interstitialAdService = InterstitialAdService();
final ThemeManager themeManager = ThemeManager();
final CallService callService = CallService();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

typedef LangCallback = void Function(String);
typedef CurrencyCallback = void Function(String);
typedef TierCallback = void Function(String);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Crashlytics
  FlutterError.onError = (details) {
    FirebaseCrashlytics.instance.recordFlutterFatalError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };
  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);

  // Performance
  await FirebasePerformance.instance.setPerformanceCollectionEnabled(true);

  try {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: AndroidAppCheckProvider.playIntegrity,
    );
  } catch (e) {
    debugPrint('AppCheck: failed — $e');
  }
  try {
    await MobileAds.instance.initialize();
    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(testDeviceIds: ['YOUR_TEST_DEVICE_ID_HERE']),
    );
    debugPrint('AdMob: initialized successfully');
  } catch (e) {
    debugPrint('AdMob: initialization failed — $e');
  }
  await GoogleSignIn.instance.initialize();
  await SecurityService().initialize();
  await themeManager.load();
  await NotificationService.initLocalNotifications();
  NotificationService.onCallNotificationTap = (data) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    Navigator.of(ctx).push(
      MaterialPageRoute(
        builder: (_) => IncomingCallScreen(
          callId: data['callId'] as String,
          callerId: data['callerId'] as String,
          callerName: data['callerName'] as String? ?? 'Unknown',
          callerImage: data['callerImage'] as String?,
          channelName: data['channelName'] as String,
          callType: data['callType'] as String? ?? 'video',
        ),
      ),
    );
  };
  notificationService.initialize();
  presenceService.initialize();
  autoLockService.initialize();
  callService.cleanupOldCalls();
  await AudioService.init(
    builder: () => AudioPlayerService.instance,
    config: AudioServiceConfig(
      androidNotificationChannelId: 'com.soko_langu.audio',
      androidNotificationChannelName: 'Soko Langu Music',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
  runApp(SokoLanguApp());
}

class AppConfig extends InheritedWidget {
  final String langCode;
  final String currencyCode;
  final String accountTier;
  final LangCallback onSetLanguage;
  final CurrencyCallback onSetCurrency;
  final TierCallback onSetTier;

  const AppConfig({
    super.key,
    required this.langCode,
    required this.currencyCode,
    required this.accountTier,
    required this.onSetLanguage,
    required this.onSetCurrency,
    required this.onSetTier,
    required super.child,
  });

  static AppConfig of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppConfig>()!;
  }

  @override
  bool updateShouldNotify(AppConfig old) =>
      langCode != old.langCode ||
      currencyCode != old.currencyCode ||
      accountTier != old.accountTier;
}

class SokoLanguApp extends StatefulWidget {
  const SokoLanguApp({super.key});

  @override
  State<SokoLanguApp> createState() => _SokoLanguAppState();
}

class _SokoLanguAppState extends State<SokoLanguApp> {
  String _langCode = 'en';
  String _currencyCode = 'TZS';
  String? _wallpaperPath;
  bool _showLockScreen = false;
  StreamSubscription? _callSubscription;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    themeManager.addListener(_onThemeChange);
    autoLockService.onLock = () {
      if (mounted) setState(() => _showLockScreen = true);
    };
    _listenForIncomingCalls();
  }

  void _listenForIncomingCalls() {
    _callSubscription = callService.incomingCallStream().listen((call) {
      if (call == null || !mounted) return;
      final ctx = navigatorKey.currentContext;
      if (ctx == null) return;
      Navigator.of(ctx).push(
        MaterialPageRoute(
          builder: (_) => IncomingCallScreen(
            callId: call['id'] as String,
            callerId: call['callerId'] as String,
            callerName: call['callerName'] as String? ?? 'Unknown',
            callerImage: call['callerImage'] as String?,
            channelName: call['channelName'] as String,
            callType: call['type'] as String? ?? 'video',
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _callSubscription?.cancel();
    themeManager.removeListener(_onThemeChange);
    presenceService.dispose();
    autoLockService.dispose();
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
      _wallpaperPath = prefs.getString('wallpaper_path');
    });
  }

  void _setLanguage(String code) {
    setState(() => _langCode = code);
  }

  void _setCurrency(String code) {
    setState(() => _currencyCode = code);
  }

  void _setTier(String tier) async {
    await themeManager.setTier(tier);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeManager.isDark;
    final isSilver = themeManager.currentTier == 'silver';

    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Soko Langu',
      theme: themeManager.lightTheme,
      darkTheme: themeManager.darkTheme,
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      home: const AuthGate(),
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
        } else if (isSilver &&
            _wallpaperPath != null &&
            File(_wallpaperPath!).existsSync()) {
          content = Stack(
            children: [
              Positioned.fill(
                child: Image.file(File(_wallpaperPath!), fit: BoxFit.cover),
              ),
              Positioned.fill(
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(color: Colors.white.withAlpha(60)),
                  ),
                ),
              ),
              content,
            ],
          );
        }
        return AppConfig(
          langCode: _langCode,
          currencyCode: _currencyCode,
          accountTier: themeManager.currentTier,
          onSetLanguage: _setLanguage,
          onSetCurrency: _setCurrency,
          onSetTier: _setTier,
          child: Stack(
            children: [
              content,
              if (_showLockScreen)
                LockScreen(
                  onUnlock: () {
                    setState(() => _showLockScreen = false);
                    autoLockService.unlock();
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}
