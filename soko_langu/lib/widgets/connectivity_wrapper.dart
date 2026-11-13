import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../extensions/context_tr.dart';
import '../services/network_state_service.dart';

/// Root-level connectivity notice. When the API is degraded or the device is
/// offline the app stays fully interactive (cache data + retry buttons work);
/// a slim non-blocking banner at the top flags the state. Driven by
/// [NetworkStateService] (single source of truth).
class ConnectivityWrapper extends StatelessWidget {
  final Widget child;
  const ConnectivityWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final status = context.watch<NetworkStateService>().status;
    if (status == NetworkStatus.online) return child;

    final cs = Theme.of(context).colorScheme;
    final isOffline = status == NetworkStatus.offline;
    final message = isOffline
        ? context.tr('no_network')
        : context.tr('network_unstable');

    return Stack(
      children: [
        child,
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: SafeArea(
            bottom: false,
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.primary.withValues(alpha: 0.4)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    isOffline
                        ? Icons.wifi_off_rounded
                        : Icons.sync_problem_rounded,
                    size: 18,
                    color: cs.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
