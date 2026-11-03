import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import 'animated_press.dart';

/// Samsung One UI Inspired Design System Tokens & Components for Soko Vibe.
///
/// Principles:
/// 1. Viewing Area vs Interaction Area: Large readable headings with comfortable breathing room.
/// 2. Comfortable 16-24px rounded corners that feel soft, modern, and human.
/// 3. Minimal clutter: High contrast, purposeful emerald green accents (#00C853 / #009624), no excessive borders.
/// 4. Thumb-friendly interaction zones for effortless one-handed use.
class OneUI {
  OneUI._();

  // ─── Radii ────────────────────────────────────────────────────────────────
  static const double rSm = 12.0;
  static const double rMd = 16.0;
  static const double rLg = 20.0;
  static const double rXl = 24.0;
  static const double rSheet = 28.0;
  static const double rFull = 999.0;

  // ─── Radii Shapes ─────────────────────────────────────────────────────────
  static final BorderRadius brSm = BorderRadius.circular(rSm);
  static final BorderRadius brMd = BorderRadius.circular(rMd);
  static final BorderRadius brLg = BorderRadius.circular(rLg);
  static final BorderRadius brXl = BorderRadius.circular(rXl);
  static final BorderRadius brSheet = const BorderRadius.vertical(top: Radius.circular(rSheet));
  static final BorderRadius brFull = BorderRadius.circular(rFull);

  // ─── Shadows & Elevation ──────────────────────────────────────────────────
  static List<BoxShadow> softShadow(BuildContext context, {double opacity = 0.04, double blur = 14}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isDark) return const [];
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: opacity),
        blurRadius: blur,
        offset: const Offset(0, 4),
      ),
    ];
  }

  static List<BoxShadow> elevatedShadow(BuildContext context, {Color? color}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shadowColor = color ?? Colors.black;
    return [
      BoxShadow(
        color: shadowColor.withValues(alpha: isDark ? 0.25 : 0.08),
        blurRadius: 18,
        offset: const Offset(0, 6),
      ),
    ];
  }

  // ─── Haptics ──────────────────────────────────────────────────────────────
  static void tapFeedback() => HapticFeedback.selectionClick();
  static void actionFeedback() => HapticFeedback.mediumImpact();
}

/// Samsung One UI Viewing Header Widget.
///
/// Displays a large, generous title and context area at the top of screens
/// that provides visual calmness and readability.
class OneUIViewingHeader extends StatelessWidget {
  const OneUIViewingHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.leading,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 12),
  });

  final String title;
  final String? subtitle;
  final Widget? action;
  final Widget? leading;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    color: cs.onSurface,
                    height: 1.2,
                  ),
                ),
              ),
              if (action != null) action!,
            ],
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Samsung One UI Grouped Card Container.
///
/// Soft, rounded container (20px radius) that groups related controls and info
/// cleanly without harsh outlines.
class OneUICard extends StatelessWidget {
  const OneUICard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    this.onTap,
    this.color,
    this.border,
    this.borderRadius,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final Color? color;
  final BoxBorder? border;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final r = borderRadius ?? OneUI.brLg;

    final cardContent = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? (isDark ? cs.surfaceContainer : cs.surface),
        borderRadius: r,
        border: border ?? Border.all(
          color: isDark ? cs.outlineVariant.withValues(alpha: 0.2) : cs.outlineVariant.withValues(alpha: 0.5),
          width: 0.8,
        ),
        boxShadow: OneUI.softShadow(context),
      ),
      child: ClipRRect(
        borderRadius: r,
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );

    if (onTap != null) {
      return AnimatedPress(
        onTap: onTap,
        pressedScale: 0.98,
        child: cardContent,
      );
    }

    return cardContent;
  }
}

/// Samsung One UI Modern Button.
class OneUIButton extends StatelessWidget {
  const OneUIButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.primary = true,
    this.height = 48,
    this.width,
    this.backgroundColor,
    this.foregroundColor,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool primary;
  final double height;
  final double? width;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;

    final bg = backgroundColor ?? (primary
        ? cs.primary
        : (isDark ? cs.surfaceContainerHigh : cs.surfaceContainerLow));
    final fg = foregroundColor ?? (primary
        ? cs.onPrimary
        : cs.onSurface);

    return SizedBox(
      height: height,
      width: width,
      child: Material(
        color: onPressed == null ? bg.withValues(alpha: 0.5) : bg,
        borderRadius: OneUI.brMd,
        elevation: primary && onPressed != null ? 1 : 0,
        shadowColor: primary ? cs.primary.withValues(alpha: 0.3) : Colors.transparent,
        child: InkWell(
          borderRadius: OneUI.brMd,
          onTap: (onPressed == null || loading) ? null : () {
            OneUI.tapFeedback();
            onPressed!();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              mainAxisSize: width == null ? MainAxisSize.min : MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading) ...[
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation<Color>(fg),
                    ),
                  ),
                  const SizedBox(width: 10),
                ] else if (icon != null) ...[
                  Icon(icon, size: 19, color: fg),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: fg,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Samsung One UI Soft Input Pill.
class OneUISearchBar extends StatelessWidget {
  const OneUISearchBar({
    super.key,
    required this.hintText,
    this.controller,
    this.onTap,
    this.onChanged,
    this.onSubmitted,
    this.readOnly = false,
    this.filterCount = 0,
    this.onFilterTap,
  });

  final String hintText;
  final TextEditingController? controller;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool readOnly;
  final int filterCount;
  final VoidCallback? onFilterTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;

    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2024) : const Color(0xFFF3F4F6),
        borderRadius: OneUI.brLg,
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Icon(Icons.search_rounded, color: cs.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              readOnly: readOnly,
              onTap: onTap,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: TextStyle(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          if (onFilterTap != null) ...[
            GestureDetector(
              onTap: () {
                OneUI.tapFeedback();
                onFilterTap!();
              },
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: filterCount > 0
                      ? cs.primary.withValues(alpha: 0.18)
                      : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04)),
                  borderRadius: OneUI.brSm,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      size: 16,
                      color: filterCount > 0 ? cs.primary : cs.onSurfaceVariant,
                    ),
                    if (filterCount > 0) ...[
                      const SizedBox(width: 4),
                      Text(
                        '$filterCount',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ] else ...[
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

/// Samsung One UI Empty State.
class OneUIEmptyState extends StatelessWidget {
  const OneUIEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: cs.primary),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
                letterSpacing: -0.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(
                fontSize: 14,
                color: cs.onSurfaceVariant,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              OneUIButton(
                label: actionLabel!,
                onPressed: onAction,
                primary: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
