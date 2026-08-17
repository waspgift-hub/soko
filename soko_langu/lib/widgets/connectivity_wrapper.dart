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
    final offline = await _isServerReachable();
    if (!mounted) return;
    if (!offline) {
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
    _retryTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      final offline = await _isServerReachable();
      if (!mounted) return;
      if (!offline) {
        _retryTimer?.cancel();
        setState(() => _offline = false);
      }
    });
  }

  Future<bool> _isServerReachable() async {
    try {
      final resp = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/ping'),
      ).timeout(const Duration(seconds: 5));
      return resp.statusCode != 200;
    } catch (_) {
      return true;
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
