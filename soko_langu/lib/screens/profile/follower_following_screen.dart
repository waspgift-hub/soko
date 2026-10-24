import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/follow_service.dart';
import '../../services/seller_verification_service.dart';
import '../../services/user_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_typography.dart';
import '../../extensions/context_tr.dart';
import '../../models/user_profile.dart';
import '../../widgets/ads/blue_tick_badge.dart';
import '../../widgets/ads/ad_slot.dart';
import '../../widgets/ads/ad_manager.dart';

/// Follower or following list screen.
///
/// Shows a paginated list of users who follow [userId] (followers) or whom
/// [userId] follows (following). Each row shows the follower/followee's avatar,
/// name, username, Blue Tick badge, and a follow/unfollow button.
///
/// Subscribes to the live follower/following stream so changes (follows,
/// unfollows, blocks) are reflected immediately.
class FollowerFollowingScreen extends StatefulWidget {
  const FollowerFollowingScreen({
    super.key,
    required this.userId,
    required this.userName,
    required this.isFollowers,
  });

  final String userId;
  final String userName;

  /// true = followers of userId; false = following of userId
  final bool isFollowers;

  @override
  State<FollowerFollowingScreen> createState() => _FollowerFollowingScreenState();
}

class _FollowerFollowingScreenState extends State<FollowerFollowingScreen> {
  final FollowService _followService = FollowService();
  final UserService _userService = UserService();
  final SellerVerificationService _verificationService =
      SellerVerificationService();

  List<String> _uids = [];
  bool _loading = true;
  bool _hasMore = true;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _uids = [];
      _hasMore = true;
    });

    try {
      final stream = widget.isFollowers
          ? _followService.streamFollowers(widget.userId)
          : _followService.streamFollowing(widget.userId);

      final streamSub = stream.listen((uids) {
        if (!mounted) return;
        setState(() {
          _uids = uids;
          _loading = false;
          _hasMore = uids.length >= 20;
        });
      });

      // Keep the subscription alive for the widget's lifetime
      _streamSub = streamSub;
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  StreamSubscription<List<String>>? _streamSub;

  @override
  void dispose() {
    _streamSub?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    _streamSub?.cancel();
    await _load();
  }

  Future<void> _toggleFollow(String uid) async {
    final currentlyFollowing =
        _followService.isFollowing(uid); // not async - need to re-check
    // Actually we need to check current state via stream - just toggle
    final result = await FollowService().follow(uid);
    // If currently following, unfollow instead
    // Simplified: just call follow/unfollow based on current UI state
    // We track locally via the stream
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isFollowers
            ? context.tr('followers')
            : context.tr('following')),
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
                  itemBuilder: (context, index) {
                    return _UserRow(
                      uid: _uids[index],
                      onFollowChanged: _refresh,
                    );
                  },
                  separatorBuilder: (_, _) => const Divider(height: 1),
                ),
              ),
    );
  }
}

/// A single row in the follower/following list.
///
/// Shows avatar, name, username, Blue Tick badge, and follow/unfollow button.
class _UserRow extends StatefulWidget {
  const _UserRow({
    required this.uid,
    required this.onFollowChanged,
  });

  final String uid;
  final VoidCallback onFollowChanged;

  @override
  State<_UserRow> createState() => _UserRowState();
}

class _UserRowState extends State<_UserRow> {
  UserProfile? _profile;
  SellerVerification? _verification;
  bool _isLoading = true;
  bool _isFollowing = false;
  bool _isMutating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await UserService().getProfile(widget.uid);
    final verification =
        await SellerVerificationService().resolve(widget.uid);
    final isFollowing = await FollowService().isFollowing(widget.uid);
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _verification = verification;
      _isFollowing = isFollowing;
      _isLoading = false;
    });
  }

  Future<void> _toggleFollow() async {
    if (_isMutating) return;
    setState(() => _isMutating = true);
    try {
      if (_isFollowing) {
        await FollowService().unfollow(widget.uid);
      } else {
        await FollowService().follow(widget.uid);
      }
      if (!mounted) return;
      widget.onFollowChanged();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _isMutating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_isLoading || _profile == null) {
      return const ListTile(
        leading: CircleAvatar(radius: 20),
        title: Text('Loading...'),
        trailing: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final isBlueTick = _verification?.isBlueTickActive == false
        ? false
        : _verification!.isBlueTickActive;

    return ListTile(
      leading: CircleAvatar(
        radius: 24,
        backgroundImage: _profile?.profileImage.isNotEmpty == true
            ? NetworkImage(_profile!.profileImage)
            : null,
        child: _profile?.profileImage.isEmpty == true
            ? const Icon(Icons.person_outline, size: 20)
            : null,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              _profile!.displayName.isNotEmpty
                  ? _profile!.displayName
                  : _profile!.username,
              style: const TextStyle(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          if (_verification?.isBlueTickActive == true)
            BlueTickBadge(sellerId: widget.uid, size: 13),
        ],
      ),
      subtitle: Text(
        '@${_profile!.username}',
        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
      ),
      trailing: _isMutating
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : FollowButton(
              sellerId: widget.uid,
              size: FollowButtonSize.small,
              onStatusChanged: widget.onFollowChanged,
            ),
    );
  }
}