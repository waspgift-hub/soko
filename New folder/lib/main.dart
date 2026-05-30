import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show File;
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
import 'package:go_router/go_router.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';
import 'services/localization_service.dart';
import 'services/presence_service.dart';
import 'services/smart_ad_service.dart';
import 'services/call_service.dart';
import 'services/security_service.dart';
import 'theme/theme_manager.dart';
import 'utils/responsive.dart';
import 'app/router.dart' as router_lib;
import 'app/app_state.dart' as app_state;
import 'app/routes.dart';

final NotificationService notificationService = NotificationService();
final LocalizationService localizationService = LocalizationService();
final PresenceService presenceService = PresenceService();
final SmartAdService smartAdService = SmartAdService();
final ThemeManager themeManager = ThemeManager();
final CallService callService = CallService();
final GoRouter appRouter = router_lib.buildRouter();

typedef LangCallback = void Function(String);
typedef CurrencyCallback = void Function(String);
typedef TierCallback = void Function(String);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Global error handlers - prevent crashes
  FlutterError.onError = (details) {
    debugPrint('Flutter Error: ${details.exception}');
    try { FirebaseCrashlytics.instance.recordFlutterFatalError(details); } catch (_) {}
  };

  ui.PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Platform Error: $error');
    try { FirebaseCrashlytics.instance.recordError(error, stack, fatal: true); } catch (_) {}
    return true;
  };

  try { await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform); } catch (e) { debugPrint('Firebase init: $e'); }
  try { FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true); } catch (e) { debugPrint('Firestore settings: $e'); }
  try { await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true); } catch (e) { debugPrint('Crashlytics: $e'); }
  try { await FirebasePerformance.instance.setPerformanceCollectionEnabled(true); } catch (e) { debugPrint('Performance: $e'); }
  try { await FirebaseAppCheck.instance.activate(providerAndroid: const AndroidPlayIntegrityProvider()); } catch (e) { debugPrint('AppCheck: $e'); }
  try { await MobileAds.instance.initialize(); } catch (e) { debugPrint('AdMob: $e'); }
  try { await GoogleSignIn.instance.initialize(); } catch (e) { debugPrint('GoogleSignIn: $e'); }
  try { await SecurityService().initialize(); } catch (e) { debugPrint('SecurityService: $e'); }
  try { await themeManager.load(); } catch (e) { debugPrint('ThemeManager: $e'); }

  try {
    final prefs = await SharedPreferences.getInstance();
    app_state.onboardingSeen = prefs.getBool('onboarding_seen') ?? false;
  } catch (e) { debugPrint('Prefs: $e'); }

  try { await NotificationService.initLocalNotifications(); } catch (e) { debugPrint('LocalNotif: $e'); }

  NotificationService.onCallNotificationTap = (data) {
    final ctx = router_lib.rootNavigatorKey.currentContext;
    if (ctx == null) return;
    try { GoRouter.of(ctx).push(AppRoutes.incomingCall, extra: data); } catch (e) { debugPrint('CallTap: $e'); }
  };
  NotificationService.onForegroundCall = (data) {
    final ctx = router_lib.rootNavigatorKey.currentContext;
    if (ctx == null) return;
    try { GoRouter.of(ctx).push(AppRoutes.incomingCall, extra: data); } catch (e) { debugPrint('FgCall: $e'); }
  };
  NotificationService.onCallAcceptFromNotification = (callId) {
    try { CallService().acceptCall(callId); } catch (e) { debugPrint('AcceptCall: $e'); }
  };
  NotificationService.onCallDeclineFromNotification = (callId) {
    try { CallService().declineCall(callId); } catch (e) { debugPrint('DeclineCall: $e'); }
  };

  NotificationService.onOrderNotificationTap = (data) {
    final ctx = router_lib.rootNavigatorKey.currentContext;
    if (ctx == null) return;
    try { GoRouter.of(ctx).push(AppRoutes.myOrders); } catch (e) { debugPrint('OrderTap: $e'); }
  };

  NotificationService.onOrderMessageTap = (data) {
    final ctx = router_lib.rootNavigatorKey.currentContext;
    if (ctx == null) return;
    final buyerId = data['buyerId'] as String? ?? '';
    final buyerName = data['buyerName'] as String? ?? 'Mnunuzi';
    try { GoRouter.of(ctx).push('${AppRoutes.chat}/$buyerId', extra: {'name': buyerName}); } catch (e) { debugPrint('OrderMsg: $e'); }
  };

  try { notificationService.initialize(); } catch (e) { debugPrint('notifService: $e'); }
  try { presenceService.initialize(); } catch (e) { debugPrint('presenceService: $e'); }
  try { callService.clearAllActiveCalls(); } catch (e) { debugPrint('clearCalls: $e'); }
  try { smartAdService.initialize(); } catch (e) { debugPrint('smartAdService: $e'); }

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
  StreamSubscription? _callSubscription;
  StreamSubscription? _callKitSubscription;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    themeManager.addListener(_onThemeChange);
    _listenForIncomingCalls();
    _listenCallKitEvents();
  }

  void _listenCallKitEvents() {
    _callKitSubscription = FlutterCallkitIncoming.onEvent.listen((event) async {
      if (event == null || !mounted) return;
      final ctx = router_lib.rootNavigatorKey.currentContext;
      if (ctx == null) return;
      final body = event.body as Map<String, dynamic>?;
      if (body == null) return;
      final extra = body['extra'] as Map<String, dynamic>?;
      if (extra == null) return;

      switch (event.event) {
        case Event.actionCallAccept:
          final callId = extra['callId'] as String;
          final callType = extra['callType'] as String;
          final callerName = extra['callerName'] as String;
          await callService.acceptCall(callId);
          if (mounted) {
            GoRouter.of(ctx).push(AppRoutes.videoCall, extra: {
              'callId': callId,
              'callType': callType,
              'remoteName': callerName,
            });
          }
          break;
        case Event.actionCallDecline:
          final callId = extra['callId'] as String;
          await callService.declineCall(callId);
          break;
        case Event.actionCallEnded:
          final callId = extra['callId'] as String;
          await callService.endCall(callId);
          break;
        case Event.actionCallTimeout:
          final callId = extra['callId'] as String;
          await callService.missCall(callId);
          break;
        case Event.actionCallIncoming:
        case Event.actionCallStart:
        case Event.actionCallToggleAudioSession:
        case Event.actionDidUpdateDevicePushTokenVoip:
        case Event.actionCallCallback:
        case Event.actionCallToggleHold:
        case Event.actionCallToggleMute:
        case Event.actionCallToggleDmtf:
        case Event.actionCallToggleGroup:
        case Event.actionCallConnected:
        case Event.actionCallCustom:
          break;
      }
    });
  }

  void _listenForIncomingCalls() {
    _callSubscription = callService.incomingCallStream().listen((call) {
      if (call == null || !mounted) return;
      final callId = call['id'] as String? ?? '';
      final callerName = call['callerName'] as String? ?? 'Incoming Call';
      final callerImage = call['callerImage'] as String? ?? '';
      final channelName = call['channelName'] as String? ?? '';
      final callType = call['type'] as String? ?? 'voice';
      callService.showCallKitUI(
        callId: callId,
        callerName: callerName,
        callerImage: callerImage,
        channelName: channelName,
        callType: callType,
        isOutgoing: false,
      );
    });
  }

  @override
  void dispose() {
    _callSubscription?.cancel();
    _callKitSubscription?.cancel();
    themeManager.removeListener(_onThemeChange);
    presenceService.dispose();
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
        } else if (isSilver &&
            _wallpaperPath != null &&
            !kIsWeb &&
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
        } else {
          content = Container(
            color: Theme.of(context).colorScheme.surface,
            child: content,
          );
        }
        return AppConfig(
          langCode: _langCode,
          currencyCode: _currencyCode,
          accountTier: themeManager.currentTier,
          onSetLanguage: _setLanguage,
          onSetCurrency: _setCurrency,
          onSetTier: _setTier,
          child: content,
        );
      },
    );
  }
}
