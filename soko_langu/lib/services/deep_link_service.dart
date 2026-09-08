import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import '../app/app_state.dart' as app_state;

/// Parses and queues HTTPS App Links / Universal Links for Soko Vibe.
///
/// The app shares links as `https://www.sokovibe.co.tz/product/{id}`. When the
/// OS hands one to this process (cold start via [AppLinks.getInitialLink], warm
/// start via [AppLinks.uriLinkStream]), it is translated into the matching
/// internal GoRouter location and held until app initialization is complete —
/// navigation is only safe once auth + router state have settled.
class DeepLinkService {
  DeepLinkService._();

  static final DeepLinkService instance = DeepLinkService._();

  /// Hosts the app is allowed to treat as its own product links.
  ///
  /// Only `www.sokovibe.co.tz` is verified live today; the bare apex
  /// `sokovibe.co.tz` has no valid TLS certificate, so shares always use the
  /// `www` host and bare-host links are rejected rather than trusting a
  /// look-alike domain.
  static const List<String> allowedHosts = [
    'www.sokovibe.co.tz',
    'sokovibe.co.tz',
  ];

  /// Public base URL used when generating share links.
  static const String webBaseUrl = 'https://www.sokovibe.co.tz';

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;
  Uri? _pending;
  bool _started = false;

  /// Navigation sink, set by the app shell once the router exists.
  void Function(String location)? onLocation;

  /// Returns the shareable web URL for a product.
  static String productShareUrl(String productId) =>
      '$webBaseUrl/product/$productId';

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
    } catch (e) {
      debugPrint('DeepLinkService: init failed — $e');
    }
  }

  void _handle(Uri uri) {
    if (kDebugMode) debugPrint('DeepLinkService: incoming $uri');
    final location = _toLocation(uri);
    if (location == null) {
      if (kDebugMode) debugPrint('DeepLinkService: ignored $uri');
      return;
    }
    _pending = uri;
    _emit();
  }

  /// Emits the stored link once the app is ready to navigate.
  void _emit() {
    final uri = _pending;
    if (uri == null) return;
    final location = _toLocation(uri);
    if (location == null) return;
    // Redirects read appStateNotifier, so navigating before init would either
    // be a no-op (appInitialized false) or wrong (auth not restored yet).
    if (!app_state.appStateNotifier.appInitialized) return;
    _pending = null;
    onLocation?.call(location);
  }

  /// Flushes a cold-start link after the shell signals app init is complete.
  void flushPending() => _emit();

  /// Translates an external URL into the internal route, or null when the URL
  /// is not a Soko Vibe deep link. Path segments keep the parser independent
  /// of query strings and trailing slashes.
  String? _toLocation(Uri uri) {
    if (uri.scheme != 'https') return null;
    if (!allowedHosts.contains(uri.host.toLowerCase())) return null;

    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length < 2) return null;

    final id = segments[1];
    if (id.length > 128) return null; // refuse oversized ids

    switch (segments[0]) {
      case 'product':
        // GoRouter already owns '/product/:id' and loads from Firestore with
        // loading + not-found states, so the deep link reuses that route.
        return '/product/$id';
      case 'seller':
        // Sellers map to the existing public profile screen.
        return '/public-profile/$id';
    }
    return null;
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}