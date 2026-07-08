import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../extensions/context_tr.dart';

/// Monitors network connectivity and shows an Instagram-style offline UI.
///
/// **Mid-session disconnect** → a thin animated banner slides down from the top.
/// **App-launch disconnect** → a full-screen fallback with logo, message, and a
/// "Try Again" button using the #4CAF50 green.
class ConnectivityWrapper extends StatefulWidget {
  final Widget child;
  const ConnectivityWrapper({super.key, required this.child});

  @override
  State<ConnectivityWrapper> createState() => _ConnectivityWrapperState();
}

class _ConnectivityWrapperState extends State<ConnectivityWrapper>
    with SingleTickerProviderStateMixin {
  bool _offline = false;
  bool _initialized = false;
  /// True when the app started while offline — prevents the banner from showing
  /// until the user has at least seen the app once online.
  bool _startedOffline = false;

  StreamSubscription<List<ConnectivityResult>>? _sub;
  late AnimationController _bannerCtrl;
  late Animation<Offset> _bannerSlide;

  @override
  void initState() {
    super.initState();

    _bannerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _bannerSlide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _bannerCtrl,
      curve: Curves.easeOutCubic,
    ));

    _sub = Connectivity().onConnectivityChanged.listen(_onChange);
    _checkInitialConnectivity();
  }

  Future<void> _checkInitialConnectivity() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (!mounted) return;
      final offline = results.every((r) => r == ConnectivityResult.none);
      setState(() {
        _offline = offline;
        _startedOffline = offline;
        _initialized = true;
      });
    } catch (_) {
      if (mounted) setState(() => _initialized = true);
    }
  }

  void _onChange(List<ConnectivityResult> results) {
    final offline = results.every((r) => r == ConnectivityResult.none);
    if (offline == _offline) return;
    if (!mounted) return;
    setState(() => _offline = offline);

    if (_startedOffline && !offline) {
      _startedOffline = false;
      return;
    }

    if (!_startedOffline) {
      if (offline) {
        _bannerCtrl.forward();
      } else {
        _bannerCtrl.reverse();
      }
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _bannerCtrl.dispose();
    super.dispose();
  }

  Future<void> _retry() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (!mounted) return;
      final offline = results.every((r) => r == ConnectivityResult.none);
      if (!offline) {
        setState(() {
          _offline = false;
          _startedOffline = false;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) return widget.child;

    if (_startedOffline && _offline) {
      return _OfflineFallback(onRetry: _retry);
    }

    return Stack(
      children: [
        widget.child,
        if (!_startedOffline)
          SlideTransition(
            position: _bannerSlide,
            child: const _OfflineBanner(),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Full-screen fallback — shown when the app starts with no connectivity
// ---------------------------------------------------------------------------

class _OfflineFallback extends StatelessWidget {
  final VoidCallback onRetry;
  const _OfflineFallback({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),
              Image.asset(
                'assets/app_icon.png',
                width: 96,
                height: 96,
                errorBuilder: (_, _, _) => Icon(
                  Icons.wifi_off,
                  size: 80,
                  color: cs.onSurface.withValues(alpha: 0.3),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                context.tr('no_internet_connection'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                context.tr('check_connection_try_again'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: onRetry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    context.tr('try_again'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top floating banner — slides down on mid-session disconnect
// ---------------------------------------------------------------------------

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.only(top: topPadding + 4, bottom: 8),
      decoration: BoxDecoration(
        color: cs.primary,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off, size: 16, color: cs.onPrimary.withValues(alpha: 0.7)),
          const SizedBox(width: 8),
          Text(
            context.tr('no_internet_connection_lower'),
            style: TextStyle(
              color: cs.onPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
