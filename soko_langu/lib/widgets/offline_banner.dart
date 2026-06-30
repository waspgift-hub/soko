import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../extensions/context_tr.dart';


class OfflineBanner extends StatefulWidget {
  final Widget child;
  const OfflineBanner({super.key, required this.child});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> with WidgetsBindingObserver {
  bool _offline = false;
  bool _initialized = false;
  late StreamSubscription<List<ConnectivityResult>> _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sub = Connectivity().onConnectivityChanged.listen(_onConnectivityChange);
    Connectivity().checkConnectivity().then((results) {
      if (mounted) {
        setState(() {
          _offline = results.every((r) => r == ConnectivityResult.none);
          _initialized = true;
        });
      }
    });
  }

  void _onConnectivityChange(List<ConnectivityResult> results) {
    final offline = results.every((r) => r == ConnectivityResult.none);
    if (mounted && offline != _offline) {
      setState(() => _offline = offline);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) return const SizedBox();
    return Stack(
      children: [
        widget.child,
        if (_offline) _OfflineOverlay(),
      ],
    );
  }
}

class _OfflineOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      child: Material(
        color: Colors.black.withValues(alpha: 0.85),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: cs.error.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.wifi_off_rounded, size: 52, color: cs.error),
              ),
              const SizedBox(height: 28),
              Text(
                context.tr('no_internet_connection'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: cs.surface,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                context.tr('enable_internet_to_continue'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: cs.surface.withValues(alpha: 0.7)),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: cs.surface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
