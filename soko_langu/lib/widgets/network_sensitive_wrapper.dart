import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../extensions/context_tr.dart';
import '../services/network_state_service.dart';

class NetworkSensitiveWrapper extends StatefulWidget {
  final Widget child;
  const NetworkSensitiveWrapper({super.key, required this.child});

  @override
  State<NetworkSensitiveWrapper> createState() => _NetworkSensitiveWrapperState();
}

class _NetworkSensitiveWrapperState extends State<NetworkSensitiveWrapper>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _slideAnim;
  late Animation<double> _opacityAnim;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _slideAnim = Tween<double>(begin: -1, end: 0).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic),
    );
    _opacityAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Banner shows for anything below fully online; the service owns the
    // probing, this widget only animates visibility.
    final offline =
        context.watch<NetworkStateService>().status != NetworkStatus.online;
    if (offline != _offline) {
      _offline = offline;
      if (offline) {
        _animCtrl.forward();
      } else {
        _animCtrl.reverse();
      }
    }
    return Stack(
      children: [
        widget.child,
        AnimatedBuilder(
          animation: _animCtrl,
          builder: (context, _) {
            if (_animCtrl.isDismissed && !_offline) {
              return const SizedBox.shrink();
            }
            return Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Transform.translate(
                offset: Offset(0, _slideAnim.value * 56),
                child: Opacity(
                  opacity: _opacityAnim.value,
                  child: _SokoVibeOfflineBanner(),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _SokoVibeOfflineBanner extends StatefulWidget {
  const _SokoVibeOfflineBanner();

  @override
  State<_SokoVibeOfflineBanner> createState() => _SokoVibeOfflineBannerState();
}

class _SokoVibeOfflineBannerState extends State<_SokoVibeOfflineBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _dotCtrl;

  @override
  void initState() {
    super.initState();
    _dotCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _dotCtrl.repeat(reverse: true);
  }

  @override
  void dispose() {
    _dotCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 56,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primary.withValues(alpha: 0.95), cs.primary.withValues(alpha: 0.85)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off_rounded, size: 18, color: cs.surface),
          const SizedBox(width: 10),
          Text(
            context.tr('offline_reconnecting', 'Hakuna mtandao — unajaribu kuunganisha'),
            style: TextStyle(color: cs.surface, fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 8),
          _BouncingDotsIndicator(controller: _dotCtrl, color: cs.surface),
        ],
      ),
    );
  }
}

class _BouncingDotsIndicator extends StatelessWidget {
  final AnimationController controller;
  final Color color;

  const _BouncingDotsIndicator({required this.controller, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final delay = i * 0.2;
            final t = (controller.value - delay).clamp(0.0, 1.0);
            final scale = 0.5 + 0.5 * t;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
