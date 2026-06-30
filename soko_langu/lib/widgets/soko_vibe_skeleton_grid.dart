import 'package:flutter/material.dart';

class SokoVibeSkeletonGrid extends StatefulWidget {
  final int itemCount;

  const SokoVibeSkeletonGrid({super.key, this.itemCount = 6});

  @override
  State<SokoVibeSkeletonGrid> createState() => _SokoVibeSkeletonGridState();
}

class _SokoVibeSkeletonGridState extends State<SokoVibeSkeletonGrid>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _shimmer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    _shimmer = Tween<double>(begin: -1, end: 2).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine),
    );
    _ctrl.repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final baseColor = isDark ? Colors.grey[850]! : Colors.grey[300]!;
    final highlightColor = isDark ? Colors.grey[700]! : Colors.grey[100]!;

    return AnimatedBuilder(
      animation: _shimmer,
      builder: (context, _) {
        return GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.7,
          ),
          itemCount: widget.itemCount,
          itemBuilder: (context, index) => _buildShimmerItem(baseColor, highlightColor),
        );
      },
    );
  }

  Widget _buildShimmerItem(Color base, Color highlight) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        color: base,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _ShimmerRect(
              color: base,
              highlight: highlight,
              shimmer: _shimmer,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
            child: _ShimmerLine(
              width: 0.8,
              height: 12,
              color: base,
              highlight: highlight,
              shimmer: _shimmer,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: _ShimmerLine(
              width: 0.45,
              height: 10,
              color: base,
              highlight: highlight,
              shimmer: _shimmer,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShimmerRect extends StatelessWidget {
  final Color color;
  final Color highlight;
  final Animation<double> shimmer;

  const _ShimmerRect({
    required this.color,
    required this.highlight,
    required this.shimmer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, highlight, color],
          stops: [shimmer.value - 0.3, shimmer.value, shimmer.value + 0.3]
              .map((s) => s.clamp(0.0, 1.0))
              .toList(),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }
}

class _ShimmerLine extends StatelessWidget {
  final double width;
  final double height;
  final Color color;
  final Color highlight;
  final Animation<double> shimmer;

  const _ShimmerLine({
    required this.width,
    required this.height,
    required this.color,
    required this.highlight,
    required this.shimmer,
  });

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: width,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          gradient: LinearGradient(
            colors: [color, highlight, color],
            stops: [shimmer.value - 0.3, shimmer.value, shimmer.value + 0.3]
                .map((s) => s.clamp(0.0, 1.0))
                .toList(),
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
    );
  }
}
