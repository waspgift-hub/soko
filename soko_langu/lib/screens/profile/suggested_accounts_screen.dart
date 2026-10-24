import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/follow_service.dart';
import '../../services/social_suggestion_service.dart';
import '../../services/user_service.dart';
import '../../services/seller_verification_service.dart';
import '../../models/social_models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_typography.dart';
import '../../theme/design_tokens.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/ads/blue_tick_badge.dart';
import '../../models/user_profile.dart';

/// Suggested accounts screen — shows recommended sellers/users to follow.
///
/// Suggestions are based on:
/// * Second-degree connections (followed by people you follow)
/// * Verified sellers (KYC approved + Blue Tick active)
///
/// Already-followed, blocked, and self accounts are excluded.
class SuggestedAccountsScreen extends StatefulWidget {
  const SuggestedAccountsScreen({super.key});

  @override
  State<SuggestedAccountsScreen> createState() => _SuggestedAccountsScreenState();
}

class _SuggestedAccountsScreenState extends State<SuggestedAccountsScreen> {
  final SocialSuggestionService _suggestionService = SocialSuggestionService();
  final FollowService _followService = FollowService();

  List<UserProfile> _suggestions = [];
  bool _loading = true;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      final suggestions = await _suggestionService.resolveSuggestions(limit: 20);
      if (!mounted) return;
      setState(() {
        _suggestions = suggestions;
        _loading = false;
        _hasMore = suggestions.length >= 20;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_suggestions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Suggested for You')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person_add_outlined, size: 64, color: cs.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                context.tr('no_suggestions_yet'),
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Suggested for You')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView.separated(
          itemCount: _suggestions.length,
          itemBuilder: (context, index) {
            return _SuggestedAccountRow(
              profile: _suggestions[index],
              onFollowed: () {
                setState(() {
                  _suggestions.removeAt(index);
                });
              },
            );
          },
          separatorBuilder: (_, _) => const Divider(height: 1),
        ),
      ),
    );
  }
}

/// A single suggested account row with a follow button.
class _SuggestedAccountRow extends StatefulWidget {
  const _SuggestedAccountRow({
    required this.profile,
    required this.onFollowed,
  });

  final UserProfile profile;
  final VoidCallback onFollowed;

  @override
  State<_SuggestedAccountRow> createState() => _SuggestedAccountRowState();
}

class _SuggestedAccountRowState extends State<_SuggestedAccountRow> {
  final FollowService _followService = FollowService();
  final SellerVerificationService _verificationService = SellerVerificationService();

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
    final verification = await _verificationService.resolve(widget.profile.uid);
    final isFollowing = await _followService.isFollowing(widget.profile.uid);
    if (!mounted) return;
    setState(() {
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
        await _followService.unfollow(widget.profile.uid);
      } else {
        await _followService.follow(widget.profile.uid);
      }
      if (!mounted) return;
      widget.onFollowed();
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

    if (_isLoading || _verification == null) {
      return const ListTile(
        leading: CircleAvatar(radius: 24),
        title: Text('Loading...'),
        trailing: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final isBlueTick = _verification!.isBlueTickActive;

    return ListTile(
      leading: CircleAvatar(
        radius: 24,
        backgroundImage: widget.profile.profileImage.isNotEmpty
            ? NetworkImage(widget.profile.profileImage)
            : null,
        child: widget.profile.profileImage.isEmpty
            ? const Icon(Icons.person_outline, size: 20)
            : null,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              widget.profile.displayName.isNotEmpty
                  ? widget.profile.displayName
                  : widget.profile.username,
              style: const TextStyle(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          if (isBlueTick)
            BlueTickBadge(sellerId: widget.profile.uid, size: 13),
        ],
      ),
      subtitle: Text(
        '@${widget.profile.username}',
        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
      ),
      trailing: _isMutating
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : FollowButton(
              sellerId: widget.profile.uid,
              size: FollowButtonSize.small,
              onStatusChanged: widget.onFollowed,
            ),
    );
  }
}