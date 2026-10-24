import 'package:flutter/material.dart';

/// Utilities for responsive typography that respect user accessibility settings.
class ResponsiveTypography {
  ResponsiveTypography._();

  /// Returns a text scale factor clamped to reasonable bounds.
  ///
  /// This allows accessibility scaling while preventing extreme scaling
  /// that would break layouts. The default Flutter text scale factor can
  /// go up to 3.0+, but we cap it at 1.5 for body text and 1.3 for headings.
  static double clampTextScale(BuildContext context, {
    double maxBodyScale = 1.5,
    double maxHeadingScale = 1.3,
    double maxDisplayScale = 1.2,
  }) {
    final scale = MediaQuery.textScalerOf(context).scale(1.0);
    return scale.clamp(1.0, maxBodyScale);
  }

  /// Returns a responsive font size that respects accessibility settings
  /// but is clamped to prevent layout breakage.
  static double responsiveFontSize(BuildContext context, double baseSize, {
    double maxScale = 1.5,
    double minSize = 10,
  }) {
    final scale = MediaQuery.textScalerOf(context).scale(1.0);
    final clampedScale = scale.clamp(1.0, maxScale);
    return (baseSize * clampedScale).clamp(minSize, double.infinity);
  }

  /// Creates a TextStyle with responsive font size.
  static TextStyle responsiveStyle(BuildContext context, TextStyle baseStyle, {
    double maxScale = 1.5,
    double minFontSize = 10,
  }) {
    final scale = MediaQuery.textScalerOf(context).scale(1.0);
    final clampedScale = scale.clamp(1.0, maxScale);
    final newSize = (baseStyle.fontSize ?? 14) * clampedScale;
    return baseStyle.copyWith(
      fontSize: newSize.clamp(minFontSize, double.infinity),
    );
  }

  /// Maximum number of lines for text that should be readable at all scales.
  /// Returns higher values for larger base font sizes to prevent clipping.
  static int maxLinesForFontSize(double fontSize) {
    if (fontSize <= 12) return 3;
    if (fontSize <= 16) return 2;
    return 1;
  }
}

/// A banner container that adapts to text scaling without clipping.
///
/// Instead of fixed height, it uses minimum height constraints and allows
/// content to expand naturally when text scales up.
class ResponsiveBanner extends StatelessWidget {
  const ResponsiveBanner({
    super.key,
    required this.child,
    this.minHeight = 180,
    this.margin,
    this.padding,
    this.decoration,
    this.onTap,
    this.borderRadius,
  });

  final Widget child;
  final double minHeight;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final Decoration? decoration;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final effectiveDecoration = decoration ?? BoxDecoration(
      borderRadius: borderRadius ?? BorderRadius.circular(20),
      color: cs.surfaceContainerLow,
    );

    final content = Padding(
      padding: padding ?? EdgeInsets.zero,
      child: child,
    );

    if (onTap != null) {
      return ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: Container(
          margin: margin,
          decoration: effectiveDecoration,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: content,
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Container(
        margin: margin,
        decoration: effectiveDecoration,
        clipBehavior: Clip.antiAlias,
        child: content,
      ),
    );
  }
}

/// A flexible text widget that prevents overflow at large text scales.
class FlexibleText extends StatelessWidget {
  const FlexibleText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow = TextOverflow.ellipsis,
    this.textAlign,
    this.softWrap = true,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow overflow;
  final TextAlign? textAlign;
  final bool softWrap;

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = style != null
        ? ResponsiveTypography.responsiveStyle(context, style!)
        : null;

    return Text(
      text,
      style: effectiveStyle,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      softWrap: softWrap,
    );
  }
}

/// A text widget specifically for banners that handles scaling gracefully.
class BannerText extends StatelessWidget {
  const BannerText(
    this.text, {
    super.key,
    required this.style,
    this.maxLines = 2,
    this.overflow = TextOverflow.ellipsis,
    this.textAlign,
  });

  final String text;
  final TextStyle style;
  final int maxLines;
  final TextOverflow overflow;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1.0);
    // Increase max lines at higher scales to prevent clipping
    final adjustedMaxLines = scale > 1.3 ? maxLines + 1 : maxLines;

    return Flexible(
      child: Text(
        text,
        style: style,
        maxLines: adjustedMaxLines,
        overflow: overflow,
        textAlign: textAlign,
        softWrap: true,
      ),
    );
  }
}

/// Wrapper that provides a minimum height based on content and text scale.
class MinHeightWrapper extends StatelessWidget {
  const MinHeightWrapper({
    super.key,
    required this.child,
    this.minHeight = 0,
    this.textScaleFactor,
  });

  final Widget child;
  final double minHeight;
  final double? textScaleFactor;

  @override
  Widget build(BuildContext context) {
    final scale = textScaleFactor ?? MediaQuery.textScalerOf(context).scale(1.0);
    // Scale minimum height proportionally to text scale
    final adjustedMinHeight = minHeight * scale.clamp(1.0, 1.5);

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: adjustedMinHeight),
      child: child,
    );
  }
}