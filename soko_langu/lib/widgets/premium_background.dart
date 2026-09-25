import 'package:flutter/material.dart';

/// Shared app surface. Uses the active Material 3 surface token so every screen
/// inherits the same background in light and dark themes.
class PremiumBackground extends StatelessWidget {
  final Widget child;

  const PremiumBackground({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: child,
    );
  }
}
