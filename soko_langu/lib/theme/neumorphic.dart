import 'package:flutter/material.dart';
import 'soko_palette.dart';

/// Separation strength for a flat surface. Flat is not shadowless — it just
/// uses one low-alpha shadow instead of the soft-UI light/shade pair.
enum NeuFlatDepth {
  /// No shadow: solid fill plus a hairline edge.
  none,

  /// Content cards resting on the canvas.
  rest,

  /// Overlays — sheets, menus, dialogs.
  overlay,
}

/// Surface tokens for the app's flat-first visual system.
///
/// The app is ~90% flat and ~10% soft-UI. [Neu.base]/[Neu.insetBase]/
/// [Neu.raised]/[Neu.inset] are the soft-UI half and are reserved for
/// *controls* — primary CTAs, the FAB, the nav bar, text/search wells and
/// active filter state. Everything that carries content (cards, list rows,
/// dialogs, sheets, menus, banners) uses the flat tokens: [canvas], [flatFill]
/// and the single-direction [flat] shadow.
///
/// Soft-UI needs its element base lifted off the canvas or the dual shadows
/// disappear, which is why [base] is the light-green secondary surface in
/// light mode and the raised dark surface in dark mode, while the flat
/// [canvas] stays soft grey / true black. The two never share a fill.
class Neu {
  Neu._();

  /// Flat app canvas. Deliberately not [base]: a soft-UI canvas would make the
  /// flat 90% read as grey-on-grey and leave the soft 10% with nothing to
  /// contrast against.
  static Color canvas(Brightness b) =>
      b == Brightness.dark ? SokoPalette.darkBackground : SokoPalette.lightBackground;

  /// Flat surface fill — the card color, one step off the canvas so a hairline
  /// edge reads in light mode and dark cards do not vanish into pure black.
  static Color flatFill(Brightness b) =>
      b == Brightness.dark ? SokoPalette.darkSurface : SokoPalette.lightCard;

  /// Single-direction flat shadow. A tinted flat shadow reads cleaner than pure
  /// black over a grey canvas, and the alpha steps are deliberately low so
  /// surfaces stay visually flush.
  static List<BoxShadow> flat(NeuFlatDepth depth, Brightness b) {
    return switch (depth) {
      NeuFlatDepth.none => const [],
      NeuFlatDepth.rest => [
        BoxShadow(
          color: shade(b).withValues(alpha: b == Brightness.dark ? 0.34 : 0.07),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ],
      NeuFlatDepth.overlay => [
        BoxShadow(
          color: shade(b).withValues(alpha: b == Brightness.dark ? 0.5 : 0.12),
          blurRadius: 28,
          offset: const Offset(0, 10),
        ),
      ],
    };
  }

  /// Element base for raised (extruded) surfaces flush with the canvas. This
  /// is the light-green secondary surface in light mode, so neutral soft
  /// controls (secondary buttons) pick up the brand tint.
  static Color base(Brightness b) => b == Brightness.dark
      ? SokoPalette.darkSurfaceSecondary
      : SokoPalette.lightSecondaryBackground;

  /// Slightly darker base for recessed fields/pressed states.
  static Color insetBase(Brightness b) =>
      b == Brightness.dark ? const Color(0xFF0B100D) : const Color(0xFFF1F4F1);

  /// Top-left glow (light source).
  static Color highlight(Brightness b) =>
      b == Brightness.dark ? const Color(0xFF23342A) : SokoPalette.lightCard;

  /// Bottom-right ambient occlusion.
  static Color shade(Brightness b) =>
      b == Brightness.dark ? SokoPalette.darkBackground : const Color(0xFFDCE3DD);

  /// Extruded dual shadow scaled by [depth] (0 disables).
  static List<BoxShadow> raised(double depth, Brightness b) {
    if (depth <= 0) return const [];
    final d = depth;
    return [
      BoxShadow(
        color: shade(b).withValues(alpha: b == Brightness.dark ? 0.5 : 0.18),
        blurRadius: d * 2,
        offset: Offset(d, d),
      ),
      BoxShadow(
        color: highlight(b).withValues(alpha: b == Brightness.dark ? 0.06 : 0.9),
        blurRadius: d * 2,
        offset: Offset(-d, -d),
      ),
    ];
  }

  /// Extruded dual shadow tinted around a colored base (green CTAs, FABs, …
  /// dark tones) instead of the neutral canvas tones.
  static List<BoxShadow> raisedHue(double depth, Color base) {
    if (depth <= 0) return const [];
    final d = depth;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.25),
        blurRadius: d * 2,
        offset: Offset(d, d),
      ),
      BoxShadow(
        color: Colors.white.withValues(alpha: 0.12),
        blurRadius: d * 2,
        offset: Offset(-d, -d),
      ),
    ];
  }

  /// Recessed fill: darker base plus a hairline groove. Pass an [accent]
  /// (e.g. primary green) to recolor the groove for the focused state of
  /// fields.
  static BoxDecoration inset(double radius, Brightness b, {Color? fill, Color? accent}) {
    return BoxDecoration(
      color: fill ?? insetBase(b),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: accent ?? grooveColor(b), width: accent != null ? 1.5 : 1),
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
