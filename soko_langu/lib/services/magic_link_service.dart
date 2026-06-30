import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../notifiers/auth_notifier.dart';

class MagicLinkService {
  static const String _emailKey = 'magic_link_email';
  final AuthNotifier _authNotifier;
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;

  MagicLinkService(this._authNotifier);

  Future<void> initialize() async {
    final initialUri = await _appLinks.getInitialLink();
    if (initialUri != null) {
      await _processLink(initialUri);
    }

    _sub = _appLinks.uriLinkStream.listen(_processLink);
  }

  Future<void> _processLink(Uri uri) async {
    try {
      final link = uri.toString();
      if (!FirebaseAuth.instance.isSignInWithEmailLink(link)) return;

      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString(_emailKey);
      if (email == null) {
        debugPrint('MagicLink: No stored email found for link: $link');
        return;
      }

      await _authNotifier.completeMagicLinkSignIn(email, link);
    } catch (e) {
      debugPrint('MagicLink: Failed to process link: $e');
    }
  }

  static Future<void> saveEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_emailKey, email);
  }

  static Future<String?> getSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_emailKey);
  }

  static Future<void> clearEmail() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_emailKey);
  }

  void dispose() {
    _sub?.cancel();
  }
}
