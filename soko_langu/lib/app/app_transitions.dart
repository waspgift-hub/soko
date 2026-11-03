import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

const Duration _forward = Duration(milliseconds: 380);
const Duration _reverse = Duration(milliseconds: 300);

/// Slightly overshooting cubic bezier used across the app for a premium feel.
const Curve appEaseOut = Cubic(0.22, 0.61, 0.36, 1);

/// Shared route helper — the single source of the screen-change animation.
/// Combines a subtle slide, fade and scale so transitions feel fast yet smooth.
Route<T> buildAppRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
  bool fullscreenDialog = false,
}) {
  return PageRouteBuilder<T>(
    settings: settings,
    fullscreenDialog: fullscreenDialog,
    transitionDuration: _forward,
    reverseTransitionDuration: _reverse,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return _buildTransition(animation, secondaryAnimation, child);
    },
  );
}

/// GoRouter page helper — keeps the same animation as [buildAppRoute].
Page<T> buildAppPage<T>(Widget child) {
  return CustomTransitionPage<T>(
    child: child,
    transitionDuration: _forward,
    reverseTransitionDuration: _reverse,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return _buildTransition(animation, secondaryAnimation, child);
    },
  );
}

/// Reusable transition widget so route helpers share one implementation.
Widget _buildTransition(
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  final curved = CurvedAnimation(parent: animation, curve: appEaseOut);
  final slide = Tween<Offset>(
    begin: const Offset(0.03, 0),
    end: Offset.zero,
  ).animate(curved);
  final scale = Tween<double>(begin: 0.985, end: 1).animate(curved);
  final fade = Tween<double>(begin: 0, end: 1).animate(curved);

  // Fade out the screen below slightly for a layered depth effect.
  final secondaryFade = Tween<double>(
    begin: 1,
    end: 0.85,
  ).animate(CurvedAnimation(parent: secondaryAnimation, curve: appEaseOut));

  return FadeTransition(
    opacity: secondaryFade,
    child: SlideTransition(
      position: slide,
      child: ScaleTransition(
        scale: scale,
        child: FadeTransition(opacity: fade, child: child),
      ),
    ),
  );
}
