import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/app_state.dart' as app_state;
import 'deep_link_parser.dart';

/// Centralized deep link handler for Soko Vibe.
///
/// Responsibilities:
/// - Listen for App Links / Universal Links via [AppLinks] (cold + warm start).
/// - Delegate URL parsing to [DeepLinkParser] — never scatter parsing in screens.
/// - Queue links until [appStateNotifier.appInitialized] is true.
/// - Preserve private links (order/otp) when unauthenticated and resume after login.
/// - Emit analytics-safe events (never log OTP or private payloads).
class DeepLinkService {
  DeepLinkService._();

  static final DeepLinkService instance = DeepLinkService._();

  static const List<String> allowedHosts = DeepLinkParser.allowedHosts;
  static const String webBaseUrl = DeepLinkParser.webBaseUrl;

  static const String _pendingPrefsKey = 'pending_deep_link';

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;
  Uri? _pending;
  String? _pendingAuthLocation;
  bool _started = false;

  /// Navigation sink, set by the app shell once the router exists.
  void Function(String location)? onLocation;

  /// Returns the shareable web URL for a product.
  static String productShareUrl(String productId) =>
      DeepLinkParser.productUrl(productId);
  static String sellerShareUrl(String sellerId) =>
      DeepLinkParser.sellerUrl(sellerId);
  static String profileShareUrl(String userId) =>
      DeepLinkParser.profileUrl(userId);
  static String orderShareUrl(String orderId) =>
      DeepLinkParser.orderUrl(orderId);
  static String categoryShareUrl(String category) =>
      DeepLinkParser.categoryUrl(category);

  /// Begins listening for links. Safe to call before Firebase init completes —
  /// results are queued and flushed by [flushPending].
  Future<void> init() async {
    if (_started) return;
    _started = true;
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handle(initial);
      _subscription = _appLinks.uriLinkStream.listen(
        _handle,
        onError: (Object e) =>
            debugPrint('DeepLinkService: uriLinkStream error — $e'),
      );
      // restore persisted pending auth link (e.g. after kill)
      await _restorePendingAuth();
    } catch (e) {
      debugPrint('DeepLinkService: init failed — $e');
    }
  }

  void _handle(Uri uri) {
    if (kDebugMode) debugPrint('DeepLinkService: incoming $uri');
    final route = DeepLinkParser.parse(uri);
    if (route == null) {
      if (kDebugMode) debugPrint('DeepLinkService: ignored $uri');
      return;
    }
    // analytics without sensitive data
    _trackDeepLink(route);
    _pending = uri;
    _emit();
  }

  /// Directly handle a raw string url (from notification or share).
  void handleString(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    _handle(uri);
  }

  /// Emits the stored link once the app is ready to navigate.
  void _emit() {
    final uri = _pending;
    if (uri == null) return;
    final route = DeepLinkParser.parse(uri);
    if (route == null) return;
    if (!app_state.appStateNotifier.appInitialized) return;

    // Private routes require auth — preserve and redirect to login.
    if (route.isPrivate && !app_state.appStateNotifier.isAuthenticated) {
      _pendingAuthLocation = route.internalLocation;
      unawaited(_persistPendingAuth(route.internalLocation));
      _pending = null;
      // router will redirect private location to /login, so navigate to login
      // explicitly to preserve intent; the persisted location is used after login
      onLocation?.call('/login');
      return;
    }

    _pending = null;
    // clear persisted if we are navigating to it
    if (_pendingAuthLocation == route.internalLocation) {
      _pendingAuthLocation = null;
      unawaited(_clearPendingAuth());
    }
    onLocation?.call(route.internalLocation);
  }

  /// Flushes a cold-start link after the shell signals app init is complete.
  void flushPending() => _emit();

  /// Called after successful authentication to resume a preserved private link.
  Future<void> consumePendingAfterAuth() async {
    final loc = _pendingAuthLocation;
    if (loc != null) {
      _pendingAuthLocation = null;
      await _clearPendingAuth();
      onLocation?.call(loc);
      return;
    }
    // also flush any normal pending that was waiting for auth
    _emit();
  }

  Future<void> _persistPendingAuth(String loc) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_pendingPrefsKey, loc);
    } catch (_) {}
  }

  Future<void> _clearPendingAuth() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_pendingPrefsKey);
    } catch (_) {}
  }

  Future<void> _restorePendingAuth() async {
    try {
      final p = await SharedPreferences.getInstance();
      final loc = p.getString(_pendingPrefsKey);
      if (loc != null && loc.isNotEmpty) {
        _pendingAuthLocation = loc;
      }
    } catch (_) {}
  }

  /// Analytics-safe — never logs ids that are sensitive beyond type.
  void _trackDeepLink(DeepLinkRoute route) {
    // do not log orderId or otp values; only the type
    if (kDebugMode) {
      debugPrint('Analytics: deep_link_opened type=${route.type}');
    }
    // TODO: wire to AnalyticsService if needed — ensure no PII
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}