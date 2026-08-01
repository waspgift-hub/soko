import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_motion.dart';

/// Soko Vibe trust strip (spec §4.6): shield + animated lock. Rendered on
/// every paid state, payment sheet, and receipt.
///
/// [label] is caller-supplied so bilingual screens can pass `context.tr(...)`.
class DsEscrowShield extends StatefulWidget {
  final String label;
  final Color? color;
  final bool compact;

  const DsEscrowShield({
    super.key,
    this.label = 'Fedha zako ziko salama Escrow',
    this.color,
    this.compact = false,
  });

  @override
  State<DsEscrowShield> createState() => _DsEscrowShieldState();
}

class _DsEscrowShieldState extends State<DsEscrowShield>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Motion.celebration,
    )..repeat(reverse: true);
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
        final lockScale = 1 + 0.08 * _controller.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Icon(Icons.shield, size: 24, color: color),
                Transform.scale(
                  scale: lockScale,
                  child: Icon(
                    Icons.lock,
                    size: widget.compact ? 10 : 12,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(width: AppSpacing.s2),
            Flexible(
              child: Text(
                widget.label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.brandTextSecondary,
                      fontSize: 12,
                    ),
              ),
            ),
          ],
        );
      },
    );
  }
}
