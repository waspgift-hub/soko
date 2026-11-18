import 'package:flutter/material.dart';

/// First-frame splash shown on cold start.
///
/// Picks the brand mark colour from the active theme brightness:
///   * light mode → black mark on white background
///   * dark mode  → white mark on black background
///
/// The mark assets are `assets/brand/logos/sokovibe_launch_black.png` and
/// `.../sokovibe_launch_white.png`. They are intentionally background-free so
/// the OS-level launch icon and this in-app splash stay identical.
class LaunchSplashScreen extends StatelessWidget {
  const LaunchSplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Colors.black : Colors.white;
    final asset = isDark
        ? 'assets/brand/logos/sokovibe_launch_white.png'
        : 'assets/brand/logos/sokovibe_launch_black.png';
    return Scaffold(
      backgroundColor: bg,
      body: Center(
        child: Image.asset(
          asset,
          width: 160,
          height: 160,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
