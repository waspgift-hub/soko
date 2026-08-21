import 'package:flutter/material.dart';
import '../../theme/app_dimens.dart';

enum DsAvatarSize { sm, md, lg }

class DsAvatar extends StatelessWidget {
  final String? imageUrl;
  final String? initials;
  final IconData? icon;
  final DsAvatarSize size;
  final Color? backgroundColor;
  final VoidCallback? onTap;

  const DsAvatar({
    super.key,
    this.imageUrl,
    this.initials,
    this.icon,
    this.size = DsAvatarSize.md,
    this.backgroundColor,
    this.onTap,
  });

  double get _dimension => switch (size) {
    DsAvatarSize.sm => 32,
    DsAvatarSize.md => 48,
    DsAvatarSize.lg => 72,
  };

  double get _fontSize => switch (size) {
    DsAvatarSize.sm => AppFontSize.xs,
    DsAvatarSize.md => AppFontSize.sm,
    DsAvatarSize.lg => AppFontSize.xl,
  };

  IconData? get _iconData => icon ?? (initials == null && imageUrl == null
      ? Icons.person_outline
      : null);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = backgroundColor ?? scheme.primary.withValues(alpha: 0.12);
    final fg = scheme.primary;

    Widget child;
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      child = ClipOval(
        child: Image.network(
          imageUrl!,
          width: _dimension,
          height: _dimension,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallback(scheme),
        ),
      );
    } else {
      child = _fallback(scheme);
    }

    final avatar = SizedBox(
      width: _dimension,
      height: _dimension,
      child: child,
    );

    if (onTap == null) return avatar;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        button: true,
        label: 'Avatar',
        child: avatar,
      ),
    );
  }

  Widget _fallback(ColorScheme scheme) {
    return Container(
      width: _dimension,
      height: _dimension,
      decoration: BoxDecoration(
        color: backgroundColor ?? scheme.primary.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: _iconData != null
          ? Icon(_iconData, size: _dimension * 0.45, color: scheme.primary)
          : Text(
              initials ?? '?',
              style: TextStyle(
                fontSize: _fontSize,
                fontWeight: FontWeight.w600,
                color: scheme.primary,
              ),
            ),
    );
  }
}
