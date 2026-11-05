import 'package:flutter/material.dart';

import '../../services/follow_service.dart';
import '../../extensions/context_tr.dart';

/// Follow / unfollow button for a user profile.
class FollowButton extends StatefulWidget {
  const FollowButton({
    super.key,
    required this.targetUserId,
    this.size = FollowButtonSize.medium,
    this.onStatusChanged,
  });

  final String targetUserId;
  final FollowButtonSize size;
  final VoidCallback? onStatusChanged;

  @override
  State<FollowButton> createState() => _FollowButtonState();
}

enum FollowButtonSize { small, medium, large }

class _FollowButtonState extends State<FollowButton> {
  FollowResult? _result;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant FollowButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetUserId != widget.targetUserId) _refresh();
  }

  Future<void> _refresh() async {
    if (widget.targetUserId.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final service = FollowService();
      final following = await service.isFollowing(widget.targetUserId);
      final blockedBy = await service.isBlockedBy(widget.targetUserId);
      final hasBlocked = await service.hasBlocked(widget.targetUserId);
      var result = FollowResult.following();
      if (hasBlocked || blockedBy) {
        result = FollowResult.blocked();
      } else if (following) {
        result = FollowResult.following();
      } else {
        final requested = await service.hasPendingFollowRequest(widget.targetUserId);
        result = requested ? FollowResult.requested() : FollowResult.error('not_following');
      }
      if (!mounted) return;
      setState(() => _result = result);
    } catch (_) {
      if (!mounted) return;
      setState(() => _result = FollowResult.error('load_failed'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggle() async {
    if (_isLoading || widget.targetUserId.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final service = FollowService();
      if (_result?.isFollowing == true) {
        await service.unfollow(widget.targetUserId);
      } else if (_result?.isRequested == true) {
        await service.cancelRequest(widget.targetUserId);
      } else {
        await service.follow(widget.targetUserId);
      }
      if (!mounted) return;
      await _refresh();
      widget.onStatusChanged?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      await _refresh();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_isLoading) return _LoadingButton(size: widget.size);
    if (widget.targetUserId.isEmpty) return const SizedBox.shrink();

    final blocked = _result?.isBlocked == true;
    final following = _result?.isFollowing == true;
    final requested = _result?.isRequested == true;

    if (blocked) {
      return _OutlinedButton(
        label: context.tr('blocked'),
        icon: Icons.block,
        color: cs.onSurfaceVariant,
        enabled: false,
        size: widget.size,
      );
    }
    if (requested) {
      return _OutlinedButton(
        label: context.tr('requested'),
        icon: Icons.hourglass_empty,
        color: cs.onSurfaceVariant,
        enabled: true,
        size: widget.size,
        onTap: _toggle,
      );
    }
    if (following) {
      return _FilledButton(
        label: context.tr('following'),
        icon: Icons.person_remove,
        color: cs.primary,
        foregroundColor: cs.onPrimary,
        size: widget.size,
        onTap: _toggle,
      );
    }
    return _FilledButton(
      label: context.tr('follow'),
      icon: Icons.person_add,
      color: cs.primary,
      foregroundColor: cs.onPrimary,
      size: widget.size,
      onTap: _toggle,
    );
  }
}

class _FilledButton extends StatelessWidget {
  const _FilledButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.foregroundColor,
    required this.size,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color foregroundColor;
  final FollowButtonSize size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _BaseButton(
      enabled: onTap != null,
      size: size,
      backgroundColor: color,
      foregroundColor: foregroundColor,
      onTap: onTap,
      child: _ButtonContent(label: label, icon: icon, color: foregroundColor, size: size),
    );
  }
}

class _OutlinedButton extends StatelessWidget {
  const _OutlinedButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.size,
    this.enabled = true,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final FollowButtonSize size;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _BaseButton(
      enabled: enabled,
      size: size,
      backgroundColor: Colors.transparent,
      foregroundColor: color,
      borderColor: color,
      onTap: onTap,
      child: _ButtonContent(label: label, icon: icon, color: color, size: size),
    );
  }
}

class _BaseButton extends StatelessWidget {
  const _BaseButton({
    required this.child,
    required this.enabled,
    required this.size,
    this.backgroundColor,
    this.foregroundColor,
    this.borderColor,
    this.onTap,
  });

  final Widget child;
  final bool enabled;
  final FollowButtonSize size;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _sizeFor(size),
      width: double.infinity,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: double.infinity,
            height: _sizeFor(size),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(20),
              border: borderColor != null ? Border.all(color: borderColor!) : null,
            ),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }

  double _sizeFor(FollowButtonSize s) {
    switch (s) {
      case FollowButtonSize.small:
        return 32.0;
      case FollowButtonSize.medium:
        return 40.0;
      case FollowButtonSize.large:
        return 48.0;
    }
  }
}

class _ButtonContent extends StatelessWidget {
  const _ButtonContent({
    required this.label,
    required this.icon,
    required this.color,
    required this.size,
  });

  final String label;
  final IconData icon;
  final Color color;
  final FollowButtonSize size;

  @override
  Widget build(BuildContext context) {
    final iconSize = size == FollowButtonSize.small ? 14.0 : 16.0;
    final fontSize = size == FollowButtonSize.small ? 11.0 : 13.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: iconSize, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600, color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _LoadingButton extends StatelessWidget {
  const _LoadingButton({required this.size});
  final FollowButtonSize size;

  @override
  Widget build(BuildContext context) {
    final h = switch (size) {
      FollowButtonSize.small => 32.0,
      FollowButtonSize.medium => 40.0,
      FollowButtonSize.large => 48.0,
    };
    return SizedBox(
      height: h,
      width: h,
      child: const Center(
        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    );
  }
}
