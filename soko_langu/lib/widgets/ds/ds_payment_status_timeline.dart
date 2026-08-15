import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_motion.dart';

/// Escrow lifecycle indicator (spec §4.6): Payment → Held → Released dots
/// with animated connectors. [step] is 0..2.
class DsPaymentStatusTimeline extends StatefulWidget {
  final int step;
  final List<String> labels;
  final Color? color;

  const DsPaymentStatusTimeline({
    super.key,
    required this.step,
    required this.labels,
    this.color,
  });

  @override
  State<DsPaymentStatusTimeline> createState() =>
      _DsPaymentStatusTimelineState();
}

class _DsPaymentStatusTimelineState extends State<DsPaymentStatusTimeline>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: Motion.sheet);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.forward();
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
    final active = widget.step.clamp(0, widget.labels.length - 1);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Row(
          children: [
            for (var i = 0; i < widget.labels.length; i++) ...[
              _Dot(
                filled: i <= active,
                color: color,
                scale: t,
              ),
              if (i < widget.labels.length - 1)
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s1,
                    ),
                    decoration: BoxDecoration(
                      color: i < active
                          ? color
                          : scheme.brandBorder,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: i == active - 1
                            ? t.clamp(0.0, 1.0)
                            : (i < active ? 1 : 0),
                        child: Container(
                          height: 2,
                          color: color,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _Dot extends StatelessWidget {
  final bool filled;
  final Color color;
  final double scale;

  const _Dot({
    required this.filled,
    required this.color,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Transform.scale(
      scale: filled ? 1 + 0.15 * scale : 1,
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: filled ? color : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(
            color: filled ? color : scheme.brandBorder,
            width: 2,
          ),
        ),
      ),
    );
  }
}
