import 'package:flutter/material.dart';

/// Solid theme-aware background — true black in dark mode, soft grey canvas
/// in light mode. Uses the scaffold color so it can never drift from the
/// theme's canvas.
class PremiumBackground extends StatelessWidget {
  final Widget child;

  const PremiumBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(color: Theme.of(context).scaffoldBackgroundColor, child: child);
  }
}
