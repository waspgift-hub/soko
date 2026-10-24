import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/follow_service.dart';
import '../../services/user_service.dart';
import '../../extensions/context_tr.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/ads/blue_tick_badge.dart';
import '../../models/user_profile.dart';

/// Blocked accounts screen — shows all accounts blocked by the current user.
///
/// The user can unblock any blocked account from here.
class BlockedAccountsScreen extends StatefulWidget {
  const BlockedAccountsScreen({super.key});

  @override
  State<BlockedAccountsScreen> createState() => _BlockedAccountsScreenState();
}

class _BlockedAccountsScreenState extends State<BlockedAccountsScreen> {
  final FollowService _followService = FollowService();
  final UserService _userService = UserService();

  List<String> _blockedUids = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      final subs = _followService.streamBlocked();
      final sub = subs.listen((uids) {
        if (!mounted) return;
        setState(() {
          _blockedUids = uids;
          _loading = false;
        });
      });
      _streamSub = sub;
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

  Future<void> _unblock(String uid) async {
    setState(() => _isMutating = true);
    try {
      await _followService.unblock(uid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unblocked')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _isMutating = false);
    }
  }

  bool _isMutating = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_blockedUids.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Blocked Accounts')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.block_outlined, size: 64, color: cs.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                context.tr('no_blocked_accounts'),
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Blocked Accounts')),
      body: ListView.separated(
        itemCount: _blockedUids.length,
        itemBuilder: (context, index) {
          return _BlockedRow(
            uid: _blockedUids[index],
            onUnblock: _unblock,
          );
        },
        separatorBuilder: (_, _) => const Divider(height: 1),
      ),
    );
  }
}

/// A single blocked account row showing the blocked user's info and an unblock
/// button.
class _BlockedRow extends StatefulWidget {
  const _BlockedRow({
    required this.uid,
    required this.onUnblock,
  });

  final String uid;
  final VoidCallback onUnblock;

  @override
  State<_BlockedRow> createState() => _BlockedRowState();
}

class _BlockedRowState extends State<_BlockedRow> {
  UserProfile? _profile;
  SellerVerification? _verification;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await UserService().getProfile(widget.uid);
    final verification = await SellerVerificationService().resolve(widget.uid);
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _verification = verification;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_isLoading || _profile == null) {
      return const ListTile(
        leading: CircleAvatar(radius: 24),
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
        backgroundImage: _profile!.profileImage.isNotEmpty
            ? NetworkImage(_profile!.profileImage)
            : null,
        child: _profile!.profileImage.isEmpty
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
          if (isBlueTick) BlueTickBadge(sellerId: widget.uid, size: 13),
        ],
      ),
      subtitle: Text(
        '@${_profile!.username}',
        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
      ),
      trailing: OutlinedButton.icon(
        onPressed: widget.onUnblock,
        icon: const Icon(Icons.block_unblocked),
        label: const Text('Unblock'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
    );
  }
}