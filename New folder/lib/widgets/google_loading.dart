import 'dart:math';
import 'package:flutter/material.dart';

class GoogleLoading extends StatefulWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const GoogleLoading({
    super.key,
    this.size = 24,
    this.color,
    this.strokeWidth = 3,
  });

  @override
  State<GoogleLoading> createState() => _GoogleLoadingState();
}

class _GoogleLoadingState extends State<GoogleLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = widget.color ?? Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SizedBox(
          width: widget.size + 16,
          height: widget.size,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(3, (i) {
              final delay = i * 0.15;
              final t = (_controller.value - delay).clamp(0.0, 1.0);
              final scale = sin(t * pi) * 0.5 + 0.5;
              return Transform.scale(
                scale: 0.3 + scale * 0.7,
                child: Container(
                  width: widget.size * 0.22,
                  height: widget.size * 0.22,
                  decoration: BoxDecoration(
                    color: themeColor.withOpacity(0.3 + scale * 0.7),
                    shape: BoxShape.circle,
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

class GoogleLoadingPage extends StatelessWidget {
  final double size;
  final Color? color;

  const GoogleLoadingPage({
    super.key,
    this.size = 32,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GoogleLoading(size: size, color: color),
    );
  }
}
