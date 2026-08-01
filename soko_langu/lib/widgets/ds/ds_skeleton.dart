import 'package:flutter/material.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_motion.dart';

enum DsSkeletonShape { box, circle, line }

/// Design-system shimmer placeholder (spec §4.5): 1.2s linear gradient sweep,
/// same geometry as the content it stands in for.
class DsSkeleton extends StatefulWidget {
  final DsSkeletonShape shape;
  final double? width;
  final double? height;

  const DsSkeleton({
    super.key,
    this.shape = DsSkeletonShape.box,
    this.width,
    this.height,
  });

  @override
  State<DsSkeleton> createState() => _DsSkeletonState();
}

class _DsSkeletonState extends State<DsSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Motion.shimmerLoop,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? const Color(0xFF222952) : const Color(0xFFE4E7EF);
    final shine = isDark ? const Color(0xFF121729) : const Color(0xFFF6F7FB);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final begin = Alignment(-1.5 + 3 * t, 0);
        final end = Alignment(1.5 - 3 * t, 0);
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            shape: widget.shape == DsSkeletonShape.circle
                ? BoxShape.circle
                : BoxShape.rectangle,
            borderRadius:
                widget.shape == DsSkeletonShape.line
                    ? BorderRadius.circular(AppRadius.full)
                    : BorderRadius.circular(AppRadius.md),
            gradient: LinearGradient(
              begin: begin,
              end: end,
              colors: [base, shine, base],
            ),
          ),
        );
      },
    );
  }
}
