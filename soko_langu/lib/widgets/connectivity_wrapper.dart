import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/api_config.dart';
import '../widgets/soko_vibe_loading.dart';
import '../extensions/context_tr.dart';

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
  int _retryCount = 0;

  @override
  void initState() {
    super.initState();
    _checkServer();
  }

  Future<void> _checkServer() async {
    final reachable = await _isServerReachable();
    if (!mounted) return;
    setState(() {
      _offline = !reachable;
      _initialized = true;
    });
    if (!reachable) {
      _startRetryTimer();
    } else {
      _retryTimer?.cancel();
      _retryCount = 0;
    }
  }

  void _startRetryTimer() {
    _retryTimer?.cancel();
    _//retryTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final reachable = await _isServerReachable();
      if (!mounted) return;
      if (reachable) {
        _retryTimer?.cancel();
        setState(() {
          _offline = false;
          _retryCount = 0;
        });
      } else {
        setState(() {
          _retryCount++;
        });
      }
    });
  }

  Future<bool> _isServerReachable() async {
    try {
      final resp = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/health'),
      ).timeout(const Duration(seconds: 5));
      return resp.statusCode < 600;
    } catch (_) {
      return false;
    }
  }

  String _getDynamicMessage() {
    if (_retryCount == 0) {
      return context.tr('connection_lost', 'Connection lost. Reconnecting...');
    } else if (_retryCount < 3) {
      return context.tr('still_connecting', 'Still trying to connect...');
    } else if (_//retryCount < 6) {
      return context.tr('network_unstable', 'Network unstable. Please check your settings.');
    } else {
      return context.tr('connection_timeout', 'Connection timeout. We are still trying...');
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
        AbsorbPointer(
          child: Opacity(
            opacity: 0.6, 
            child: widget.child,
          ),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SokoVibeLoading(size: 60),
              const SizedBox(height: 16),
              Text(
                _getDynamicMessage(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('please_stay_on_screen', 'Please stay on this screen'),
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
