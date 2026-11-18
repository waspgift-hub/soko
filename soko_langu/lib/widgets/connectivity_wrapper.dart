import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../extensions/context_tr.dart';
import '../services/network_state_service.dart';

/// Root-level connectivity notice. When the API is degraded or the device is
/// offline the app stays fully interactive (cache data + retry buttons work);
/// a slim non-blocking banner flags the state.
///
/// The tree structure is deliberately **stable**: the app content always sits
/// at `Stack.children[0]` and only the banner slot is added or removed. An
/// earlier version returned either `child` or `Stack(child, banner)`, which
/// makes Flutter discard the whole subtree below it — including the router's
/// `Navigator` — every time the network flapped. That is what produced the
/// `_dependents.isEmpty` and `child._parent == this` assertions when a route
/// or dialog held inherited-widget dependencies at that exact moment.
class ConnectivityWrapper extends StatelessWidget {
  final Widget child;
  const ConnectivityWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final network = context.watch<NetworkStateService>();
    final status = network.status;
    final offline = status != NetworkStatus.online;

    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (offline) _ConnectivityBanner(
          isOffline: status == NetworkStatus.offline,
          onRetry: network.retry,
        ),
      ],
    );
  }
}

class _ConnectivityBanner extends StatefulWidget {
  final bool isOffline;
  final Future<void> Function() onRetry;

  const _ConnectivityBanner({required this.isOffline, required this.onRetry});

  @override
  State<_ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<_ConnectivityBanner> {
  bool _retrying = false;

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await widget.onRetry();
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final message = widget.isOffline
        ? context.tr('no_network', 'Hakuna mtandao. Angalia muunganisho wako.')
        : context.tr('network_unstable', 'Mtandao ni wa kutokuaminika.');

    return Positioned(
      left: 12,
      right: 12,
      top: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: (widget.isOffline ? cs.error : cs.primary)
                      .withValues(alpha: 0.35),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: (widget.isOffline ? cs.error : cs.primary)
                          .withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      widget.isOffline
                          ? Icons.wifi_off_rounded
                          : Icons.sync_problem_rounded,
                      size: 16,
                      color: widget.isOffline ? cs.error : cs.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  if (_retrying)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    TextButton(
                      onPressed: _retry,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 34),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        context.tr('try_again', 'Jaribu tena'),
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
