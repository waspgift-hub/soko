import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../extensions/context_tr.dart';
import '../services/api_config.dart';

class ConnectivityWrapper extends StatefulWidget {
  final Widget child;
  const ConnectivityWrapper({super.key, required this.child});

  @override
  State<ConnectivityWrapper> createState() => _ConnectivityWrapperState();
}

class _ConnectivityWrapperState extends State<ConnectivityWrapper> {
  bool _offline = false;
  bool _initialized = false;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _checkServer();
  }

  Future<void> _checkServer() async {
    final reachable = await _isServerReachable();
    if (!mounted) return;
    if (reachable) {
      setState(() {
        _offline = false;
        _initialized = true;
      });
      _retryTimer?.cancel();
      return;
    }
    setState(() {
      _offline = true;
      _initialized = true;
    });
    _startRetryTimer();
  }

  void _startRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      final reachable = await _isServerReachable();
      if (!mounted) return;
      if (reachable) {
        _retryTimer?.cancel();
        setState(() => _offline = false);
      }
    });
  }

  Future<bool> _isServerReachable() async {
    try {
      // Any HTTP response (even 503) proves network + server reachability.
      // /health is the canonical endpoint (there is no /ping route).
      final resp = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/health'),
      ).timeout(const Duration(seconds: 5));
      return resp.statusCode < 600;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized || !_offline) return widget.child;

    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: _OfflineBanner(
              onRetry: () {
                _retryTimer?.cancel();
                _checkServer();
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  final VoidCallback onRetry;
  const _OfflineBanner({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Material(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onRetry,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                Icon(Icons.cloud_off_rounded, color: cs.onErrorContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.tr('no_internet_connection'),
                    style: TextStyle(
                      color: cs.onErrorContainer,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(Icons.refresh_rounded, color: cs.onErrorContainer, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
