import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../extensions/context_tr.dart';
import '../services/network_state_service.dart';
import 'soko_vibe_loading.dart';

/// Root-level gate: dims the app and shows a reconnecting overlay while
/// the API is unreachable. Driven by [NetworkStateService] (single source
/// of truth) instead of its own probe timer.
class ConnectivityWrapper extends StatelessWidget {
  final Widget child;
  const ConnectivityWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final status = context.watch<NetworkStateService>().status;
    if (status == NetworkStatus.online) return child;

    final message = status == NetworkStatus.offline
        ? context.tr(
            'connection_lost', 'Connection lost. Reconnecting...')
        : context.tr('network_unstable',
            'Network unstable. Please check your settings.');

    return Stack(
      children: [
        AbsorbPointer(
          child: Opacity(
            opacity: 0.6,
            child: child,
          ),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SokoVibeLoading(size: 60),
              const SizedBox(height: 16),
              Text(
                message,
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
                context.tr(
                    'please_stay_on_screen', 'Please stay on this screen'),
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
