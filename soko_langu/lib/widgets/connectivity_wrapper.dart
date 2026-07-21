import 'dart:async';
import 'dart:convert';
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

class _ConnectivityWrapperState extends State<ConnectivityWrapper>
    with SingleTickerProviderStateMixin {
  bool _offline = false;
  bool _initialized = false;
  Timer? _retryTimer;

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
    _retryTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
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
    _bannerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) return const SizedBox();

    if (_offline) {
      return _OfflineFallback(
        onRetry: () {
          _retryTimer?.cancel();
          _checkServer();
        },
      );
    }

    return widget.child;
  }
}

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
