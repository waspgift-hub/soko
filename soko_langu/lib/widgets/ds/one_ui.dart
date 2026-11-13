import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Samsung One UI-inspired helpers for Soko Vibe.
///
/// Uses the app's existing [ColorScheme]/theme as the source of truth so the
/// Soko Vibe brand identity and dark/light behavior stay consistent.
class OneUI {
  OneUI._();

  static const double rSm = 12;
  static const double rMd = 16;
  static const double rLg = 20;
  static const double rXl = 24;
  static const double rSheet = 28;
  static const double rFull = 999;

  static final BorderRadius brSm = BorderRadius.circular(rSm);
  static final BorderRadius brMd = BorderRadius.circular(rMd);
  static final BorderRadius brLg = BorderRadius.circular(rLg);
  static final BorderRadius brXl = BorderRadius.circular(rXl);
  static final BorderRadius brFull = BorderRadius.circular(rFull);

  static List<BoxShadow> softShadow(
    BuildContext context, {
    double opacity = 0.05,
    double blur = 16,
  }) {
    if (Theme.of(context).brightness == Brightness.dark) return const [];
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: opacity),
        blurRadius: blur,
        offset: const Offset(0, 4),
      ),
    ];
  }

  static void tapFeedback() => HapticFeedback.selectionClick();

  static Color cardColor(ColorScheme cs) =>
      cs.brightness == Brightness.dark ? cs.surfaceContainerHigh : cs.surface;

  static Color canvasColor(ColorScheme cs) =>
      cs.brightness == Brightness.dark ? cs.surface : cs.surfaceContainerLowest;
}

/// Large, readable header inspired by Samsung One UI's viewing area.
class OneUIViewingHeader extends StatelessWidget {
  const OneUIViewingHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.leading,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 12),
  });

  final String title;
  final String? subtitle;
  final Widget? action;
  final Widget? leading;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme;
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (leading case final l?) ...[l, const SizedBox(width: 12)],
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: (style.headlineMedium ?? const TextStyle()).copyWith(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.6,
                    height: 1.15,
                    color: cs.onSurface,
                  ),
                ),
              ),
              ?action,
            ],
          ),
          if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: (style.bodyMedium ?? const TextStyle()).copyWith(
                fontSize: 14,
                height: 1.4,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Rounded, low-clutter grouped card container.
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
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final r = borderRadius ?? OneUI.brLg;
    final decoration = BoxDecoration(
      color: color ?? OneUI.cardColor(cs),
      borderRadius: r,
      border:
          border ??
          Border.all(
            color: cs.outlineVariant.withValues(
              alpha: cs.brightness == Brightness.dark ? 0.35 : 0.55,
            ),
            width: 0.8,
          ),
      boxShadow: OneUI.softShadow(context),
    );
    Widget content = Container(
      margin: margin,
      decoration: decoration,
      child: ClipRRect(
        borderRadius: r,
        child: Padding(padding: padding, child: child),
      ),
    );
    if (onTap == null) return content;
    return _OneUIPressable(onTap: onTap!, reduceMotion: reduceMotion, child: content);
  }
}

class _OneUIPressable extends StatefulWidget {
  const _OneUIPressable({required this.child, required this.onTap, required this.reduceMotion});
  final Widget child;
  final VoidCallback onTap;
  final bool reduceMotion;
  @override
  State<_OneUIPressable> createState() => _OneUIPressableState();
}

class _OneUIPressableState extends State<_OneUIPressable> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final scale = widget.reduceMotion ? 1.0 : (_pressed ? 0.985 : 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: () {
        OneUI.tapFeedback();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: scale,
        duration: Duration(milliseconds: widget.reduceMotion ? 0 : 120),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

/// Primary/secondary action button with comfortable touch target.
class OneUIButton extends StatelessWidget {
  const OneUIButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.primary = true,
    this.height = 50,
    this.width,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool primary;
  final double height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onPressed != null && !loading;
    final bg = primary ? cs.primary : cs.surfaceContainerHighest;
    final fg = primary ? cs.onPrimary : cs.onSurface;
    return SizedBox(
      height: height,
      width: width,
      child: FilledButton(
        onPressed: enabled
            ? () {
                OneUI.tapFeedback();
                onPressed!();
              }
            : null,
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          disabledBackgroundColor: bg.withValues(alpha: 0.45),
          disabledForegroundColor: fg.withValues(alpha: 0.55),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: OneUI.brMd),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
        child: loading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation<Color>(fg),
                ),
              )
            : Row(
                mainAxisSize: width == null ? MainAxisSize.min : MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[Icon(icon, size: 19), const SizedBox(width: 8)],
                  Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
              ),
      ),
    );
  }
}

/// Comfortable search field with optional filter action.
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
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(
          alpha: cs.brightness == Brightness.dark ? 0.75 : 1,
        ),
        borderRadius: OneUI.brLg,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
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
              style: TextStyle(color: cs.onSurface, fontSize: 15, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          if (onFilterTap != null)
            IconButton(
              onPressed: () {
                OneUI.tapFeedback();
                onFilterTap!();
              },
              tooltip: 'Filters',
              icon: Badge(
                isLabelVisible: filterCount > 0,
                label: Text('$filterCount'),
                child: Icon(
                  Icons.tune_rounded,
                  color: filterCount > 0 ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Consistent empty state for lists and discovery surfaces.
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 38, color: cs.primary),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, height: 1.45, color: cs.onSurfaceVariant),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 22),
                OneUIButton(label: actionLabel!, onPressed: onAction),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Helper for Samsung-style large title app bars in scroll views.
SliverAppBar buildOneUISliverAppBar(
  BuildContext context, {
  required String title,
  List<Widget>? actions,
  Widget? leading,
  PreferredSizeWidget? bottom,
}) {
  final cs = Theme.of(context).colorScheme;
  return SliverAppBar(
    pinned: true,
    expandedHeight: 112,
    scrolledUnderElevation: 0,
    backgroundColor: cs.surface,
    surfaceTintColor: Colors.transparent,
    leading: leading,
    actions: actions,
    bottom: bottom,
    flexibleSpace: FlexibleSpaceBar(
      titlePadding: const EdgeInsetsDirectional.only(start: 20, bottom: 14, end: 16),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: cs.onSurface,
          fontWeight: FontWeight.w700,
          fontSize: 20,
          letterSpacing: -0.4,
        ),
      ),
    ),
  );
}
