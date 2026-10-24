import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/follow_service.dart';
import '../../services/seller_verification_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/ads/blue_tick_badge.dart';

/// Follow / unfollow button for a seller or user profile.
///
/// Button state is driven by [FollowService]. The Blue Tick badge beside the
/// button shows whether the target seller has a verified badge (KYC approved +
/// Blue Tick active).
///
/// States:
/// * [following] — unfollow when tapped
/// * [requested] — awaiting approval from a private account; tapping cancels
/// * [blocked] — either account blocked the other; not tappable
/// * [not_following] — follow when tapped (or request for private accounts)
///
/// Disabled while a network call is in flight.
class FollowButton extends StatefulWidget {
  const FollowButton({
    super.key,
    required this.targetUserId,
    this.size = FollowButtonSize.medium,
    this.onStatusChanged,
  });

  /// uid of the target user to follow / unfollow.
  final String targetUserId;

  final FollowButtonSize size;

  /// Optional callback fired whenever the followed state changes.
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

  Future<void> _refresh() async {
    if (widget.targetUserId.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final following = await FollowService().isFollowing(widget.targetUserId);
      final blockedBy = await FollowService().isBlockedBy(widget.targetUserId);
      final hasBlocked = await FollowService().hasBlocked(widget.targetUserId);
      if (!mounted) return;
      setState(() {
        if (hasBlocked || blockedBy) {
          _result = FollowResult.blocked();
        } else if (following) {
          _result = FollowResult.following();
        } else {
          _result = FollowResult.requested();
        }
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggle() async {
    if (_isLoading || widget.targetUserId.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final currentlyFollowing = _result?.isFollowing == true;
      if (currentlyFollowing) {
        await FollowService().unfollow(widget.targetUserId);
      } else {
        await FollowService().follow(widget.targetUserId);
      }
      if (!mounted) return;
      setState(() => _result = null);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _cancelRequest() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      await FollowService().cancelRequest(widget.targetUserId);
      if (!mounted) return;
      setState(() => _result = null);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_isLoading) {
      return _LoadingButton(size: widget.size);
    }
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
        onTap: _cancelRequest,
      );
    }

    if (following) {
      return _FilledButton(
        label: context.tr('following'),
        icon: Icons.person_remove,
        color: cs.primary,
        size: widget.size,
        onTap: _toggle,
      );
    }

    return _FilledButton(
      label: context.tr('follow'),
      icon: Icons.person_add,
      color: cs.primary,
      size: widget.size,
      onTap: _toggle,
    );
  }
}

/// Filled (solid) primary button.
class _FilledButton extends StatelessWidget {
  const _FilledButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.size,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final FollowButtonSize size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _BaseButton(
      child: _ButtonContent(label: label, icon: icon, color: color, size: size),
      enabled: onTap != null,
      size: size,
      backgroundColor: color,
      foregroundColor: Theme.of(context).colorScheme.surface,
      onTap: onTap,
    );
  }
}

/// Outlined (transparent fill) button.
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
      child: _ButtonContent(label: label, icon: icon, color: color, size: size),
      enabled: enabled,
      size: size,
      backgroundColor: Colors.transparent,
      foregroundColor: color,
      borderColor: color,
      onTap: onTap,
    );
  }
}

/// Base button rendering.
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

/// Button content: icon + label.
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
      mainAxisAlignment: MainAxisSize.center,
      children: [
        Icon(icon, size: iconSize, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Loading placeholder shown while the follow state is being resolved.
class _LoadingButton extends StatelessWidget {
  const _LoadingButton({required this.size});

  final FollowButtonSize size;

  @override
  Widget build(BuildContext context) {
    final effectiveSize = _sizeFor(size);
    return SizedBox(
      height: effectiveSize,
      width: effectiveSize,
      child: SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
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