import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

const Duration _forward = Duration(milliseconds: 320);
const Duration _reverse = Duration(milliseconds: 240);
const Curve appEaseOut = Cubic(0.22, 0.61, 0.36, 1);

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
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        _buildTransition(context, animation, secondaryAnimation, child),
  );
}

Page<T> buildAppPage<T>(Widget child) {
  return CustomTransitionPage<T>(
    child: child,
    transitionDuration: _forward,
    reverseTransitionDuration: _reverse,
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        _buildTransition(context, animation, secondaryAnimation, child),
  );
}

Widget _buildTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
    return child;
  }
  final curved = CurvedAnimation(
    parent: animation,
    curve: appEaseOut,
    reverseCurve: Curves.easeInCubic,
  );
  final fade = Tween<double>(begin: 0, end: 1).animate(curved);
  final slide = Tween<Offset>(begin: const Offset(0.028, 0), end: Offset.zero).animate(curved);
  final scale = Tween<double>(begin: 0.992, end: 1).animate(curved);
  final secondaryFade = Tween<double>(
    begin: 1,
    end: 0.94,
  ).animate(CurvedAnimation(parent: secondaryAnimation, curve: appEaseOut));

  return FadeTransition(
    opacity: secondaryFade,
    child: FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: slide,
        child: ScaleTransition(scale: scale, child: child),
      ),
    ),
  );
}
