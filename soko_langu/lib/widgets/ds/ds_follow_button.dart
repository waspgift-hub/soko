import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../services/follow_service.dart';
import '../../theme/app_dimens.dart';
import '../auth_wall.dart';

/// Relationship-aware follow button: Follow / Following / Follow Back /
/// Friends, with loading and error rollback. State comes from streams so
/// a rejected request automatically restores the previous label.
class DsFollowButton extends StatefulWidget {
  final String userId;
  final bool compact;

  const DsFollowButton({
    super.key,
    required this.userId,
    this.compact = false,
  });

  @override
  State<DsFollowButton> createState() => _DsFollowButtonState();
}

class _DsFollowButtonState extends State<DsFollowButton> {
  final FollowService _follow = FollowService();
  bool _busy = false;

  bool get _isSelf {
    final me = FirebaseAuth.instance.currentUser?.uid ?? '';
    return me.isNotEmpty && me == widget.userId;
  }

  Future<bool> _isFollowedBy() async {
    final me = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (me.isEmpty) return false;
    try {
      final followers = await _follow.getFollowers(me).first;
      return followers.any((e) => (e['id'] ?? e['userId']) == widget.userId);
    } catch (_) {
      return false;
    }
  }

  Future<void> _toggle(bool following) async {
    if (_busy) return;
    if (FirebaseAuth.instance.currentUser == null) {
      await requireAuth(context);
      return;
    }
    setState(() => _busy = true);
    try {
      if (following) {
        await _follow.unfollow(widget.userId);
      } else {
        await _follow.follow(widget.userId);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Follow failed. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isSelf) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<bool>(
      stream: _follow.isFollowingStream(widget.userId),
      builder: (context, snap) {
        final following = snap.data ?? false;
        if (!snap.hasData) {
          return OutlinedButton(
            onPressed: null,
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? 12 : 20,
                vertical: widget.compact ? 6 : 10,
              ),
              shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(AppRadius.md)),
            ),
            child: const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return FutureBuilder<bool>(
          future: _isFollowedBy(),
          builder: (context, backSnap) {
            final followedBy = backSnap.data ?? false;
            final label = !following && !followedBy
                ? 'Follow'
                : !following && followedBy
                    ? 'Follow Back'
                    : following && followedBy
                        ? 'Friends'
                        : 'Following';
            final primary = !following;
            return _busy
                ? OutlinedButton(
                    onPressed: null,
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        horizontal: widget.compact ? 12 : 20,
                        vertical: widget.compact ? 6 : 10,
                      ),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppRadius.md)),
                    ),
                    child: const SizedBox(
                      width: 14,
                      height: 14,
                      child:
                          CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : primary
                    ? ElevatedButton(
                        onPressed: () => _toggle(following),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                          padding: EdgeInsets.symmetric(
                            horizontal: widget.compact ? 12 : 20,
                            vertical: widget.compact ? 6 : 10,
                          ),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  AppRadius.md)),
                        ),
                        child: Text(label),
                      )
                    : OutlinedButton(
                        onPressed: () => _toggle(following),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.symmetric(
                            horizontal: widget.compact ? 12 : 20,
                            vertical: widget.compact ? 6 : 10,
                          ),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  AppRadius.md)),
                        ),
                        child: Text(label),
                      );
          },
        );
      },
    );
  }
}
