import 'package:flutter/material.dart';
import 'neumorphic.dart';

/// How a surface is allowed to be rendered.
enum SurfaceStyle {
  /// Solid fill, hairline edge, at most a single low-alpha shadow. The app
  /// default — roughly 90% of every screen.
  flat,

  /// Extruded: dual shadows sharing one top-left light source.
  raised,

  /// Recessed: darker fill plus a hairline groove, reads as pressed into the
  /// surrounding surface.
  inset,
}

/// The job a UI element does, independent of which screen it appears on.
///
/// The app is flat-first with a deliberate ~10% soft-UI accent. Keying the
/// visual treatment to the *role* rather than to individual screens is what
/// keeps that ratio from drifting as screens are added or redesigned.
enum SurfaceRole {
  // ── Soft (the ~10%) — interactive controls only ──────────────────────────

  /// The one high-commitment action on a screen ("Buy Now", "Pay", "Post").
  primaryCta,

  /// Floating action button and other always-on shortcuts.
  floatingAction,

  /// Persistent bottom navigation.
  navBar,

  /// Search input.
  searchField,

  /// Any other text entry well.
  textField,

  /// Selected filter / tab / segment — the "pressed in" active state.
  activeFilter,

  // ── Flat (the ~90%) — anything that carries content ──────────────────────

  /// Product, order, payment and profile cards.
  card,

  /// Rows inside a list or settings menu.
  listRow,

  /// Modal dialog.
  dialog,

  /// Bottom sheet.
  sheet,

  /// Popup or context menu.
  menu,

  /// Promotional or status banner.
  banner,

  /// Unselected chip.
  chip,

  /// Section separator.
  divider,
}

/// Resolves [SurfaceRole] to its fixed [SurfaceStyle], and renders the matching
/// decoration. This is the single place the flat/soft mix is decided — widgets
/// ask for a role rather than choosing a shadow treatment themselves.
class SurfacePolicy {
  const SurfacePolicy._();

  /// The soft-UI roles. Everything outside this set is flat.
  static const Set<SurfaceRole> softRoles = {
    SurfaceRole.primaryCta,
    SurfaceRole.floatingAction,
    SurfaceRole.navBar,
    SurfaceRole.searchField,
    SurfaceRole.textField,
    SurfaceRole.activeFilter,
  };

  /// The fixed style for [role].
  static SurfaceStyle styleFor(SurfaceRole role) => switch (role) {
        SurfaceRole.primaryCta ||
        SurfaceRole.floatingAction ||
        SurfaceRole.navBar =>
          SurfaceStyle.raised,
        SurfaceRole.searchField ||
        SurfaceRole.textField ||
        SurfaceRole.activeFilter =>
          SurfaceStyle.inset,
        _ => SurfaceStyle.flat,
      };

  /// Whether [role] is one of the soft-UI accents.
  static bool isSoft(SurfaceRole role) => softRoles.contains(role);

  /// Decoration for [role].
  ///
  /// [fill] defaults to the style's canonical colour: flat surfaces get a fill
  /// one step off the canvas, raised/inset get the soft-UI element base. Pass
  /// [fill] to tint it (a green CTA, for instance, pairs with
  /// [Neu.raisedHue] rather than [Neu.raised]).
  ///
  /// [borderRadius] overrides [radius] for surfaces that are rounded on some
  /// edges only — sheets and drawers.
  static BoxDecoration decorate(
    SurfaceRole role,
    Brightness b, {
    required double radius,
    BorderRadius? borderRadius,
    Color? fill,
    Color? borderColor,
    BoxBorder? border,
    double depth = 3,
  }) {
    final style = styleFor(role);
    final resolved = fill ?? _defaultFill(style, b);
    final resolvedRadius = borderRadius ?? BorderRadius.circular(radius);

    return switch (style) {
      SurfaceStyle.raised => BoxDecoration(
          color: resolved,
          borderRadius: resolvedRadius,
          boxShadow: Neu.raised(depth, b),
        ),
      SurfaceStyle.inset => Neu.inset(
          radius,
          b,
          fill: resolved,
          accent: borderColor,
        ),
      SurfaceStyle.flat => BoxDecoration(
          color: resolved,
          borderRadius: resolvedRadius,
          border: border ??
              Border.all(
                color: borderColor ?? Neu.grooveColor(b),
                width: 0.5,
              ),
          boxShadow: Neu.flat(_flatDepth(role), b),
        ),
    };
  }

  static Color _defaultFill(SurfaceStyle style, Brightness b) =>
      switch (style) {
        SurfaceStyle.raised => Neu.base(b),
        SurfaceStyle.inset => Neu.insetBase(b),
        SurfaceStyle.flat => Neu.flatFill(b),
      };

  /// Sheets, dialogs and menus float above content; cards and rows rest on it.
  static NeuFlatDepth _flatDepth(SurfaceRole role) => switch (role) {
        SurfaceRole.sheet ||
        SurfaceRole.dialog ||
        SurfaceRole.menu =>
          NeuFlatDepth.overlay,
        _ => NeuFlatDepth.rest,
      };
}
