import 'dart:async';

import 'package:flutter/material.dart';

import '../../extensions/context_tr.dart';
import '../../services/follow_service.dart';
import '../../services/seller_verification_service.dart';
import '../../services/user_service.dart';
import '../../widgets/ads/blue_tick_badge.dart';
import '../../widgets/social/follow_button.dart';

class FollowerFollowingScreen extends StatefulWidget {
  const FollowerFollowingScreen({
    super.key,
    required this.userId,
    required this.userName,
    required this.isFollowers,
  });

  final String userId;
  final String userName;
  final bool isFollowers;

  @override
  State<FollowerFollowingScreen> createState() => _FollowerFollowingScreenState();
}

class _FollowerFollowingScreenState extends State<FollowerFollowingScreen> {
  final FollowService _followService = FollowService();
  StreamSubscription<List<String>>? _streamSub;
  List<String> _uids = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final stream = widget.isFollowers
        ? _followService.streamFollowers(widget.userId)
        : _followService.streamFollowing(widget.userId);
    _streamSub = stream.listen(
      (uids) {
        if (!mounted) return;
        setState(() {
          _uids = uids;
          _loading = false;
        });
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _loading = false);
      },
    );
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isFollowers ? context.tr('followers') : context.tr('following')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _uids.isEmpty
          ? Center(
              child: Text(
                widget.isFollowers
                    ? context.tr('no_followers_yet')
                    : context.tr('not_following_anyone'),
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            )
          : ListView.separated(
              itemCount: _uids.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: Theme.of(context).dividerColor),
              itemBuilder: (context, index) => _UserRow(uid: _uids[index]),
            ),
    );
  }
}

class _UserRow extends StatefulWidget {
  const _UserRow({required this.uid});
  final String uid;

  @override
  State<_UserRow> createState() => _UserRowState();
}

class _UserRowState extends State<_UserRow> {
  UserProfile? _profile;
  bool _blueTick = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await UserService().getProfile(widget.uid);
      final verification = await SellerVerificationService().resolve(widget.uid);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _blueTick = verification?.isBlueTickActive ?? false;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) {
      return const ListTile(
        leading: CircleAvatar(radius: 20),
        title: SizedBox(height: 12),
        trailing: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final profile = _profile;
    if (profile == null) return const SizedBox.shrink();
    final name = profile.displayName.isNotEmpty ? profile.displayName : profile.username;
    return ListTile(
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: cs.surfaceContainerHighest,
        backgroundImage: profile.profileImage.isNotEmpty
            ? NetworkImage(profile.profileImage)
            : null,
        child: profile.profileImage.isEmpty
            ? Icon(Icons.person_outline, color: cs.onSurfaceVariant)
            : null,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              name,
              style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_blueTick) ...[
            const SizedBox(width: 6),
            BlueTickBadge(sellerId: widget.uid, size: 13),
          ],
        ],
      ),
      subtitle: profile.username.isNotEmpty
          ? Text('@${profile.username}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))
          : null,
      trailing: SizedBox(
        width: 118,
        child: FollowButton(targetUserId: widget.uid, size: FollowButtonSize.small),
      ),
    );
  }
}
