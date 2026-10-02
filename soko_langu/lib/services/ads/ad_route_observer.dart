import 'package:flutter/widgets.dart';

import 'ad_config.dart';
import 'ad_manager.dart';

/// Feeds the current route into [AdManager] so the ad system always knows which
/// screen is on top.
///
/// This is what makes critical-flow suppression reliable. Previously the
/// interstitial timer lived in the app shell, which stays mounted across every
/// `context.push`, so an ad could surface on top of checkout, a payment sheet,
/// OTP entry or the KYC form. Centralising the route means one check covers
/// every screen without each screen having to opt out.
///
/// Registered via `GoRouter.observers` in `lib/app/router.dart`.
class AdRouteObserver extends NavigatorObserver {
  AdRouteObserver(this._manager);

  final AdManager _manager;

  /// go_router names every page from its route path, so `settings.name` is the
  /// location string. A non-page push (dialog, modal sheet) inherits whatever is
  /// already tracked, which is the correct behaviour: an ad must not become
  /// eligible just because a bottom sheet opened on top of a safe screen.
  static String? _locationOf(Route<dynamic>? route) {
    if (route == null) return null;
    final name = route.settings.name;
    if (name == null || name.isEmpty) return null;
    final uri = Uri.tryParse(name);
    if (uri == null) return null;
    return uri.path.isEmpty ? name : uri.path;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _sync(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _sync(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _sync(newRoute ?? oldRoute);
  }

  void _sync(Route<dynamic>? route) {
    final location = _locationOf(route);
    if (location != null) _manager.currentRoute = location;
  }
}

/// Fires a placement-controlled interstitial at a deliberate transition point.
///
/// Fire-and-forget on purpose: the caller navigates immediately and the ad, if
/// allowed, presents on top. Marketplace navigation must never block on ad
/// loading, and a failure to load is never visible to the user.
void requestInterstitialOn(BuildContext context, AdPlacement placement) {
  assert(placement.isFullscreen, '$placement is not a fullscreen placement');
  adManagerOf(context).showInterstitial(placement);
}
