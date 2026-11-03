import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../extensions/context_tr.dart';
import '../services/api_config.dart';

/// App-wide network status surface.
/// Network loss never freezes the marketplace; server-dependent actions can
/// fail normally while already-rendered UI stays usable.
class ConnectivityWrapper extends StatefulWidget {
  final Widget child;

  const ConnectivityWrapper({
    super.key,
    required this.child,
  });

  @override
  State<ConnectivityWrapper> createState() => _ConnectivityWrapperState();
}

class _ConnectivityWrapperState extends State<ConnectivityWrapper> {
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _healthDebounce;
  bool _hasNetwork = true;
  bool _serverReachable = true;
  bool _checking = false;

  bool get _offline => !_hasNetwork || !_serverReachable;

  @override
  void initState() {
    super.initState();
    _listenToConnectivity();
    unawaited(_refreshNetworkState());
  }

  void _listenToConnectivity() {
    _subscription = Connectivity().onConnectivityChanged.listen((results) {
      final connected =
          results.any((result) => result != ConnectivityResult.none);

      if (!mounted) return;
      setState(() => _hasNetwork = connected);

      if (connected) {
        _scheduleHealthCheck();
      } else {
        _healthDebounce?.cancel();
        setState(() => _serverReachable = false);
      }
    });
  }

  Future<void> _refreshNetworkState() async {
    try {
      final results = await Connectivity().checkConnectivity();
      final connected =
          results.any((result) => result != ConnectivityResult.none);

      if (!mounted) return;
      setState(() => _hasNetwork = connected);

      if (connected) {
        await _checkServer();
      } else {
        setState(() => _serverReachable = false);
      }
    } catch (_) {
      // Advisory only.
    }
  }

  void _scheduleHealthCheck() {
    _healthDebounce?.cancel();
    _healthDebounce = Timer(
      const Duration(milliseconds: 500),
      () => unawaited(_checkServer()),
    );
  }

  Future<void> _checkServer() async {
    if (!mounted || !_hasNetwork || _checking) return;

    setState(() => _checking = true);

    try {
      final response = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/health'))
          .timeout(const Duration(seconds: 5));

      if (!mounted) return;
      setState(() {
        _serverReachable =
            response.statusCode >= 200 && response.statusCode < 500;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _serverReachable = false);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  void dispose() {
    _healthDebounce?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        IgnorePointer(
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            offset: _offline ? Offset.zero : const Offset(0, -1.2),
            child: SafeArea(
              bottom: false,
              child: Align(
                alignment: Alignment.topCenter,
                child: _NetworkBanner(
                  checking: _checking,
                  hasNetwork: _hasNetwork,
                  colorScheme: cs,
                  onRetry: _checkServer,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NetworkBanner extends StatelessWidget {
  final bool checking;
  final bool hasNetwork;
  final ColorScheme colorScheme;
  final VoidCallback onRetry;

  const _NetworkBanner({
    required this.checking,
    required this.hasNetwork,
    required this.colorScheme,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.inverseSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          if (checking)
            SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                color: colorScheme.onInverseSurface,
              ),
            )
          else
            Icon(
              hasNetwork ? Icons.cloud_off_outlined : Icons.wifi_off_rounded,
              size: 17,
              color: colorScheme.onInverseSurface,
            ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              hasNetwork
                  ? context.tr(
                      'server_unavailable',
                      'Network is available, but Soko Vibe is temporarily unavailable.',
                    )
                  : context.tr(
                      'connection_lost',
                      'You are offline. Some actions need an internet connection.',
                    ),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.onInverseSurface,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          if (hasNetwork)
            TextButton(
              onPressed: onRetry,
              child: Text(context.tr('retry', 'Retry')),
            ),
        ],
      ),
    );
  }
}
