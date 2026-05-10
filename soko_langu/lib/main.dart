import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';
import 'services/localization_service.dart';
import 'services/auto_lock_service.dart';
import 'services/presence_service.dart';
import 'services/interstitial_ad_service.dart';
import 'screens/auth/auth_gate.dart';
import 'screens/auth/lock_screen.dart';
import 'theme/theme_manager.dart';

final NotificationService notificationService = NotificationService();
final LocalizationService localizationService = LocalizationService();
final AutoLockService autoLockService = AutoLockService();
final PresenceService presenceService = PresenceService();
final InterstitialAdService interstitialAdService = InterstitialAdService();
final ThemeManager themeManager = ThemeManager();

typedef LangCallback = void Function(String);
typedef CurrencyCallback = void Function(String);
typedef TierCallback = void Function(String);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  MobileAds.instance.initialize();
  await GoogleSignIn.instance.initialize();
  await themeManager.load();
  notificationService.initialize();
  presenceService.initialize();
  autoLockService.initialize();
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

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    themeManager.addListener(_onThemeChange);
    autoLockService.onLock = () {
      if (mounted) setState(() => _showLockScreen = true);
    };
  }

  @override
  void dispose() {
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
    final theme = themeManager.currentTheme;
    final isSilver = themeManager.currentTier == 'silver';

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Soko Langu',
      theme: theme,
      home: const AuthGate(),
      builder: (context, child) {
        return AppConfig(
          langCode: _langCode,
          currencyCode: _currencyCode,
          accountTier: themeManager.currentTier,
          onSetLanguage: _setLanguage,
          onSetCurrency: _setCurrency,
          onSetTier: _setTier,
          child: Stack(
            children: [
              if (isSilver &&
                  _wallpaperPath != null &&
                  File(_wallpaperPath!).existsSync())
                Positioned.fill(
                  child: Image.file(File(_wallpaperPath!), fit: BoxFit.cover),
                ),
              if (isSilver)
                Positioned.fill(
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(color: Colors.white.withAlpha(60)),
                    ),
                  ),
                ),
              child!,
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
