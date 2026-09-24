import 'package:flutter/material.dart';

/// Neumorphic surface tokens — "soft UI" dual shadows sharing one light source
/// (top-left) so raised elements read as carved from the same canvas as the
/// scaffold. Light theme keeps a white canvas (brand §black/white) with a
/// near-white element base; dark theme lifts the base just above the near-black
/// canvas so the pure-black bottom-right shadow stays visible.
class Neu {
  Neu._();

  /// Element base for raised (extruded) surfaces flush with the canvas.
  static Color base(Brightness b) =>
      b == Brightness.dark ? const Color(0xFF171920) : const Color(0xFFF0F1F5);

  /// Slightly darker base for recessed fields/pressed states.
  static Color insetBase(Brightness b) =>
      b == Brightness.dark ? const Color(0xFF101218) : const Color(0xFFE9EAF0);

  /// Top-left glow (light source).
  static Color highlight(Brightness b) =>
      b == Brightness.dark ? const Color(0xFF2E313D) : const Color(0xFFFFFFFF);

  /// Bottom-right ambient occlusion.
  static Color shade(Brightness b) =>
      b == Brightness.dark ? const Color(0xFF000000) : const Color(0xFFD5D9E0);

  /// Extruded dual shadow scaled by [depth] (0 disables).
  static List<BoxShadow> raised(double depth, Brightness b) {
    if (depth <= 0) return const [];
    return [
      BoxShadow(
        color: shade(b),
        offset: Offset(depth, depth),
        blurRadius: depth * 2,
        spreadRadius: depth * 0.25,
      ),
      BoxShadow(
        color: highlight(b),
        offset: Offset(-depth, -depth),
        blurRadius: depth * 2,
        spreadRadius: depth * 0.25,
      ),
    ];
  }

  /// Extruded dual shadow tinted around a colored base (green CTAs, FABs, …
  /// dark tones) instead of the neutral canvas tones.
  static List<BoxShadow> raisedHue(double depth, Color base) {
    if (depth <= 0) return const [];
    return [
      BoxShadow(
        color: Color.lerp(base, Colors.black, 0.38)!,
        offset: Offset(depth, depth),
        blurRadius: depth * 2,
        spreadRadius: depth * 0.25,
      ),
      BoxShadow(
        color: Color.lerp(base, Colors.white, 0.55)!,
        offset: Offset(-depth, -depth),
        blurRadius: depth * 2,
        spreadRadius: depth * 0.25,
      ),
    ];
  }

  /// Recessed fill: darker base plus a hairline groove. Pass an [accent]
  /// (e.g. primary green) to recolor the groove for the focused state of
  /// fields.
  static BoxDecoration inset(
    double radius,
    Brightness b, {
    Color? fill,
    Color? accent,
  }) {
    return BoxDecoration(
      color: fill ?? insetBase(b),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: accent ?? grooveColor(b),
        width: accent != null ? 1.5 : 1,
      ),
    );
  }

  /// Uniform recessed-groove tint. Flutter asserts when a per-side multi-color
  /// [Border] is combined with a [BorderRadius], so the two-tone groove
  /// collapses to one blended stroke; the darker inset base still reads as a
  /// recessed field.
  static Color grooveColor(Brightness b) {
    final blend = Color.lerp(shade(b), highlight(b), 0.5)!;
    return blend.withValues(alpha: b == Brightness.dark ? 0.55 : 0.5);
  }
}