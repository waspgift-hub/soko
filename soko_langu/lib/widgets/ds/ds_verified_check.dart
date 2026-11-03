import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';

/// Brand-green verified check with a subtle pulse on first appearance
/// (spec §4.6).
class DsVerifiedCheck extends StatefulWidget {
  final double size;
  final Color? color;

  const DsVerifiedCheck({super.key, this.size = 14, this.color});

  @override
  State<DsVerifiedCheck> createState() => _DsVerifiedCheckState();
}

class _DsVerifiedCheckState extends State<DsVerifiedCheck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _pulsing = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: Motion.celebration)
      ..forward()
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          // single pulse, then rest
          setState(() => _pulsing = false);
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = widget.color ?? scheme.brandSuccess;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final scale = _pulsing ? 1 + 0.25 * _controller.value : 1.0;
        return Transform.scale(
          scale: scale,
          child: Icon(Icons.verified, size: widget.size, color: color),
        );
      },
    );
  }
}
