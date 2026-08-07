import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_motion.dart';
import 'ds_button.dart';

/// Design-system empty state (spec §17): 48dp icon in a 96dp 10%-tint circle,
/// title, secondary body, and a single primary CTA. Entrance scales 0.9→1.
class DsEmptyState extends StatefulWidget {
  final IconData icon;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? tint;

  const DsEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
    this.tint,
  });

  @override
  State<DsEmptyState> createState() => _DsEmptyStateState();
}

class _DsEmptyStateState extends State<DsEmptyState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Motion.cardEnter,
    );
    _fade = CurvedAnimation(parent: _controller, curve: Motion.easeOutCubic);
    _scale = Tween<double>(begin: 0.9, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Motion.easeOutCubic),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = widget.tint ?? scheme.primary;

    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: _scale,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s6,
            vertical: AppSpacing.s8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(widget.icon, size: 48, color: tint),
              ),
              const SizedBox(height: AppSpacing.s5),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (widget.body != null) ...[
                const SizedBox(height: AppSpacing.s2),
                Text(
                  widget.body!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.brandTextSecondary,
                      ),
                ),
              ],
              if (widget.actionLabel != null && widget.onAction != null) ...[
                const SizedBox(height: AppSpacing.s6),
                DsButton(
                  label: widget.actionLabel!,
                  onPressed: widget.onAction,
                  height: 48,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
