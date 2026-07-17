import 'package:flutter/material.dart';

class GlassmorphismCard extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final double borderRadius;
  final double blurSigma;
  final double borderOpacity;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Gradient? gradient;
  final List<BoxShadow>? boxShadow;
  final bool animate;

  const GlassmorphismCard({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.borderRadius = 24,
    this.blurSigma = 15,
    this.borderOpacity = 0.15,
    this.padding,
    this.margin,
    this.gradient,
    this.boxShadow,
    this.animate = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final effectiveGradient = gradient ?? LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? [cs.surface.withValues(alpha: 0.3), cs.surface.withValues(alpha: 0.15)]
          : [Colors.white.withValues(alpha: 0.35), Colors.white.withValues(alpha: 0.18)],
    );

    final effectiveShadow = boxShadow ?? [
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
        blurRadius: 20,
        offset: const Offset(0, 8),
      ),
    ];

    Widget card = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Stack(
        children: [
          Container(
            width: width,
            height: height,
            padding: padding,
            margin: margin,
            decoration: BoxDecoration(
              gradient: effectiveGradient,
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: borderOpacity * 0.5)
                    : Colors.white.withValues(alpha: borderOpacity),
                width: 0.5,
              ),
              boxShadow: effectiveShadow,
            ),
            child: child,
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(borderRadius),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: isDark ? 0.04 : 0.08),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.white.withValues(alpha: isDark ? 0.02 : 0.04),
                    ],
                    stops: const [0.0, 0.3, 0.7, 1.0],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (animate) {
      card = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, 20 * (1 - value)),
              child: child,
            ),
          );
        },
        child: card,
      );
    }

    return card;
  }
}

class GlassScaffold extends StatelessWidget {
  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;
  final Color? backgroundColor;
  final bool extendBodyBehindAppBar;
  final Widget? floatingActionButton;

  const GlassScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.bottomNavigationBar,
    this.backgroundColor,
    this.extendBodyBehindAppBar = false,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: extendBodyBehindAppBar,
      appBar: appBar,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: backgroundColor != null
                ? [backgroundColor!, backgroundColor!.withValues(alpha: 0.9)]
                : isDark
                    ? [cs.surface.withValues(alpha: 0.97), cs.surfaceContainerLow, cs.surface.withValues(alpha: 0.97)]
                    : [cs.surface.withValues(alpha: 0.95), cs.surfaceContainerLow, cs.surface.withValues(alpha: 0.95)],
          ),
        ),
        child: body,
      ),
    );
  }
}
