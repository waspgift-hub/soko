import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/layout/site_shell.dart';

/// Base page wrapper for routed content pages.
class ContentPage extends StatelessWidget {
  final String currentPath;
  final Widget child;
  final String? titleKey;

  const ContentPage({
    super.key,
    required this.currentPath,
    required this.child,
    this.titleKey,
  });

  @override
  Widget build(BuildContext context) {
    return SiteShell(
      currentPath: currentPath,
      child: Container(color: SokoBrand.paper, child: child),
    );
  }
}
