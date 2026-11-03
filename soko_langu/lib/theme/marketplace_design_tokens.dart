import 'package:flutter/material.dart';

/// SokoVibe marketplace design tokens.
///
/// Keep marketplace surfaces quiet so real product imagery, price and seller
/// trust signals carry the visual hierarchy. These tokens are intentionally
/// small and reusable rather than screen-specific magic numbers.
abstract final class MarketplaceTokens {
  static const double pageHorizontal = 16;
  static const double sectionGap = 24;
  static const double itemGap = 12;
  static const double compactGap = 8;

  static const double imageRadius = 10;
  static const double controlRadius = 10;
  static const double sheetRadius = 20;

  static const double hairline = 1;
  static const double touchTarget = 44;

  static const Duration quickMotion = Duration(milliseconds: 160);
  static const Duration standardMotion = Duration(milliseconds: 220);

  static const Curve standardCurve = Curves.easeOutCubic;

  static TextStyle productTitle(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium!.copyWith(
        fontWeight: FontWeight.w600,
        height: 1.25,
      );

  static TextStyle productPrice(BuildContext context) =>
      Theme.of(context).textTheme.titleSmall!.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.15,
      );

  static TextStyle metadata(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall!.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        height: 1.25,
      );
}
