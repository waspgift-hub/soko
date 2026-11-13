import 'dart:async';

import 'package:flutter/material.dart';

import '../../extensions/context_tr.dart';
import '../../models/social_models.dart';
import '../../services/follow_service.dart';
import '../../services/user_service.dart';
import '../../widgets/blue_tick_badge.dart';

class FollowRequestsScreen extends StatefulWidget {
  const FollowRequestsScreen({super.key});

  @override
  State<FollowRequestsScreen> createState() => _FollowRequestsScreenState();
}

class _FollowRequestsScreenState extends State<FollowRequestsScreen> {
  final FollowService _followService = FollowService();
  StreamSubscription<List<FollowRequest>>? _streamSub;
  List<FollowRequest> _requests = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _streamSub = _followService.streamIncomingRequests().listen(
      (requests) {
        if (!mounted) return;
        setState(() {
          _requests = requests;
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
      appBar: AppBar(title: Text(context.tr('follow_requests'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _requests.isEmpty
          ? Center(
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
            )
          : ListView.separated(
              itemCount: _requests.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: Theme.of(context).dividerColor),
              itemBuilder: (context, index) => _RequestTile(request: _requests[index]),
            ),
    );
  }
}

class _RequestTile extends StatefulWidget {
  const _RequestTile({required this.request});
  final FollowRequest request;

  @override
  State<_RequestTile> createState() => _RequestTileState();
}

class _RequestTileState extends State<_RequestTile> {
  UserProfile? _profile;
  bool _loading = true;
  bool _mutating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await UserService().getProfile(widget.request.requesterId);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_mutating) return;
    setState(() => _mutating = true);
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) {
      return const ListTile(
        leading: CircleAvatar(radius: 24),
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
          const SizedBox(width: 6),
          BlueTickBadge(sellerId: widget.request.requesterId, size: 13),
        ],
      ),
      subtitle: profile.username.isNotEmpty
          ? Text('@${profile.username}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))
          : null,
      trailing: _mutating
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton(
                  onPressed: () =>
                      _run(() => FollowService().acceptRequest(widget.request.requesterId)),
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: const Size(0, 36),
                  ),
                  child: Text(context.tr('approve'), style: const TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () =>
                      _run(() => FollowService().rejectRequest(widget.request.requesterId)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cs.onSurfaceVariant,
                    side: BorderSide(color: Theme.of(context).dividerColor),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: const Size(0, 36),
                  ),
                  child: Text(context.tr('reject'), style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
    );
  }
}
