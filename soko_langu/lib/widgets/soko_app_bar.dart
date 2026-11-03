import 'package:flutter/material.dart';
import '../theme/app_dimens.dart';
import '../theme/app_typography.dart';

/// Branded back button with a min 44dp touch target and the localized
/// back-button tooltip for screen readers.
class SokoBackButton extends StatelessWidget {
  final Color? color;
  final VoidCallback? onPressed;

  const SokoBackButton({super.key, this.color, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: color ?? cs.onSurface),
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    );
  }
}

/// Centered branded [AppBar]: the standard screen header everywhere, so every
/// page shares the same back affordance, title style and action layout.
class SokoAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final bool showBackButton;
  final VoidCallback? onBack;
  final PreferredSizeWidget? bottom;
  final Color? backgroundColor;

  const SokoAppBar({
    super.key,
    required this.title,
    this.actions,
    this.showBackButton = true,
    this.onBack,
    this.bottom,
    this.backgroundColor,
  });

  @override
  Size get preferredSize => Size.fromHeight(
        kToolbarHeight + (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: backgroundColor ?? Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      leading: showBackButton ? SokoBackButton(color: cs.onSurface, onPressed: onBack) : null,
      title: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.appBarTheme.titleTextStyle ??
              AppTypography.appBarTitle(cs.onSurface),
        ),
      ),
      actions: actions,
      bottom: bottom,
    );
  }
}