import 'package:flutter/material.dart';

/// Centers content with a 1280 max width so large monitors keep breathing room.
class ResponsiveContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const ResponsiveContainer({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 24),
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1280),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
