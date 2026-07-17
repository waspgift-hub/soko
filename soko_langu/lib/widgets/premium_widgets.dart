import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../theme/app_dimens.dart';
import 'google_loading.dart';

export '../theme/app_dimens.dart';

class PremiumScaffold extends StatelessWidget {
  final Widget child;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;
  final Color? backgroundColor;
  const PremiumScaffold({super.key, required this.child, this.appBar, this.bottomNavigationBar, this.backgroundColor});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: appBar, body: child, bottomNavigationBar: bottomNavigationBar, backgroundColor: backgroundColor);
}

class PremiumButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  const PremiumButton({super.key, required this.label, this.onPressed, this.isLoading = false});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          padding: const EdgeInsets.symmetric(vertical: AppInsets.lg),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
        child: isLoading
            ? const GoogleLoading(size: 20, strokeWidth: 2)
            : Text(label, style: const TextStyle(fontSize: AppFontSize.lg, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class GlassCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final BorderRadius? borderRadius;
  final Color? borderColor;
  const GlassCard({super.key, required this.child, this.onTap, this.padding, this.margin, this.width, this.borderRadius, this.borderColor});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final card = ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(AppRadius.lg),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          width: width,
          margin: margin,
          padding: padding ?? const EdgeInsets.all(AppInsets.lg),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow.withValues(alpha: 0.3),
            borderRadius: borderRadius ?? BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: borderColor?.withValues(alpha: 0.5) ?? cs.primary.withValues(alpha: 0.25), width: 1.2),
            boxShadow: [
              BoxShadow(color: cs.primary.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4)),
            ],
          ),
          child: child,
        ),
      ),
    );
    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: card);
    }
    return card;
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;
  const SectionHeader({super.key, required this.title, this.actionLabel, this.onAction, this.trailing});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppInsets.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 5, height: 24, decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [cs.primary, cs.primary.withValues(alpha: 0.4)],
                ),
                borderRadius: BorderRadius.circular(3),
              )),
              const SizedBox(width: 10),
              Text(title, style: TextStyle(fontSize: AppFontSize.lg, fontWeight: FontWeight.w600, color: cs.onSurface)),
              const Spacer(),
              if (actionLabel != null)
                GestureDetector(
                  onTap: onAction,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [cs.primary.withValues(alpha: 0.15), cs.primary.withValues(alpha: 0.08)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: cs.primary.withValues(alpha: 0.15)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(actionLabel!, style: TextStyle(fontSize: AppFontSize.sm, color: cs.primary, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_forward_ios, size: 10, color: cs.primary),
                      ],
                    ),
                  ),
                ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  const EmptyStateWidget({super.key, required this.icon, required this.title, this.subtitle, this.actionLabel, this.onAction});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
          const SizedBox(height: AppInsets.md),
          Text(title, style: TextStyle(fontSize: AppFontSize.lg, color: cs.onSurfaceVariant)),
          if (subtitle != null) ...[
            const SizedBox(height: AppInsets.xs),
            Text(subtitle!, style: TextStyle(fontSize: AppFontSize.sm, color: cs.onSurfaceVariant.withValues(alpha: 0.6))),
          ],
          if (actionLabel != null) ...[
            const SizedBox(height: AppInsets.md),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
