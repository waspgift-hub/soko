import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/follow_service.dart';
import '../../services/user_service.dart';
import '../../models/social_models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_typography.dart';
import '../../theme/design_tokens.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/ads/blue_tick_badge.dart';
import '../../models/user_profile.dart';

/// Follow requests screen — shows pending follow requests sent to the
/// current user (private account requests).
///
/// The account owner can approve or reject each request. Approving creates
/// the follow relationship; rejecting removes the request.
class FollowRequestsScreen extends StatefulWidget {
  const FollowRequestsScreen({super.key});

  @override
  State<FollowRequestsScreen> createState() => _FollowRequestsScreenState();
}

class _FollowRequestsScreenState extends State<FollowRequestsScreen> {
  final FollowService _followService = FollowService();
  final UserService _userService = UserService();

  List<FollowRequest> _requests = [];
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
      final subs = _followService.streamIncomingRequests();
      final sub = subs.listen((requests) {
        if (!mounted) return;
        setState(() => _requests = requests);
        _loading = false;
      });
      _streamSub = sub;
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  StreamSubscription<List<FollowRequest>>? _streamSub;

  @override
  void dispose() {
    _streamSub?.cancel();
    super.dispose();
  }

  Future<void> _approve(String requesterId) async {
    setState(() => _isMutating = true);
    try {
      await _followService.approveRequest(requesterId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Follow request approved')),
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

  Future<void> _reject(String requesterId) async {
    setState(() => _isMutating = true);
    try {
      await _followService.rejectRequest(requesterId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request rejected')),
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

    if (_requests.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Follow Requests')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person_add_outlined, size: 64, color: cs.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                context.tr('no_follow_requests'),
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Follow Requests')),
      body: ListView.separated(
        itemCount: _requests.length,
        itemBuilder: (context, index) {
          final request = _requests[index];
          return _RequestTile(
            request: request,
            onApprove: _approve,
            onReject: _reject,
          );
        },
        separatorBuilder: (_, _) => const Divider(height: 1),
      ),
    );
  }
}

/// A single follow request row showing the requester's info and approve/reject
/// buttons.
class _RequestTile extends StatefulWidget {
  const _RequestTile({
    required this.request,
    required this.onApprove,
    required this.onReject,
  });

  final FollowRequest request;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  State<_RequestTile> createState() => _RequestTileState();
}

class _RequestTileState extends State<_RequestTile> {
  UserProfile? _profile;
  bool _isLoading = true;
  bool _isMutating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await UserService().getProfile(widget.request.requesterId);
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _isLoading = false;
    });
  }

  Future<void> _handleAction(Future<void> Function() action) async {
    if (_isMutating) return;
    setState(() => _isMutating = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request updated')),
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
          BlueTickBadge(sellerId: widget.request.requesterId, size: 13),
        ],
      ),
      subtitle: Text(
        '@${_profile!.username}',
        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
      ),
      trailing: _isMutating
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(
                  onPressed: () => _handleAction(() => _widget.onApprove(widget.request.requesterId)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.surface,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  child: const Text('Approve', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => _handleAction(() => _widget.onReject(widget.request.requesterId)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: cs.onSurfaceVariant),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  child: const Text('Reject', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
        ),
      );
    }
  }
}