import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../services/user_service.dart';
import '../../services/username_service.dart';
import '../../widgets/verified_badge.dart';
import '../../extensions/context_tr.dart';

class UserSearchScreen extends StatefulWidget {
  const UserSearchScreen({super.key});

  @override
  State<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends State<UserSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final UserService _userService = UserService();
  Timer? _debounce;
  List<UserProfile> _results = [];
  bool _loading = false;
  bool _hasSearched = false;
  String? _error;
  int _page = 0;
  static const int _pageSize = 20;
  bool _hasMore = true;
  bool _loadingMore = false;
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    final q = text.trim();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _hasSearched = false;
        _error = null;
        _hasMore = true;
        _page = 0;
      });
      return;
    }
    // 400ms debounce
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(q));
  }

  Future<void> _search(String query, {bool loadMore = false}) async {
    final clean = query.trim();
    if (clean.isEmpty) return;
    if (loadMore) {
      if (_loadingMore || !_hasMore) return;
      setState(() => _loadingMore = true);
    } else {
      setState(() {
        _loading = true;
        _error = null;
        _page = 0;
        _hasMore = true;
      });
    }

    try {
      // primary: usernameService + userService.searchUsers
      List<UserProfile> res;
      // if query starts with @, treat as username exact
      if (clean.startsWith('@')) {
        final uid = await UsernameService.instance.resolveToUid(clean);
        if (uid != null) {
          final p = await _userService.getProfile(uid);
          res = p != null ? [p] : [];
        } else {
          res = [];
        }
      } else {
        res = await _userService.searchUsers(clean);
      }
      // paginate locally (Firestore queries limited)
      final start = loadMore ? (_page + 1) * _pageSize : 0;
      final end = (start + _pageSize).clamp(0, res.length);
      final pageSlice = res.sublist(0, end);
      final hasMore = res.length > end;

      if (!mounted) return;
      setState(() {
        if (loadMore) {
          _results = pageSlice;
          _page += 1;
          _hasMore = hasMore;
          _loadingMore = false;
        } else {
          _results = pageSlice;
          _hasSearched = true;
          _loading = false;
          _hasMore = hasMore;
          _page = 0;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_hasMore && !_loadingMore && _controller.text.trim().isNotEmpty) {
      await _search(_controller.text, loadMore: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('search_users_title', 'Search users')),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _controller,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: context.tr('search_seller_or_user',
                    'Search seller or user...'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          _onChanged('');
                          setState(() {});
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                filled: true,
                fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
              ),
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            )
          else if (_error != null)
            _buildError(cs)
          else if (!_hasSearched)
            _buildInitialHint(cs)
          else if (_results.isEmpty)
            _buildEmpty(cs)
          else
            Expanded(child: _buildResults(cs)),
        ],
      ),
    );
  }

  Widget _buildInitialHint(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(Icons.person_search, size: 48, color: cs.primary.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text(
            context.tr('search_users_hint',
                'Search by username, display name or @handle'),
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildError(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(Icons.error_outline, color: cs.error),
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: cs.error)),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => _search(_controller.text),
            child: Text(context.tr('retry', 'Retry')),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(Icons.search_off, size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text(context.tr('no_users_found', 'No users found'),
              style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            context.tr('try_different_username', 'Try a different name or @username'),
            style: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.7), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(ColorScheme cs) {
    return ListView.separated(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount: _results.length + (_hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        if (i >= _results.length) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: _loadingMore
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : TextButton(
                      onPressed: _loadMore,
                      child: Text(context.tr('load_more', 'Load more')),
                    ),
            ),
          );
        }
        final u = _results[i];
        return ListTile(
          leading: CircleAvatar(
            radius: 24,
            backgroundColor: cs.primaryContainer,
            backgroundImage:
                u.profileImage.isNotEmpty ? NetworkImage(u.profileImage) : null,
            child: u.profileImage.isEmpty
                ? Icon(Icons.person, color: cs.onPrimaryContainer)
                : null,
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  u.displayName.isNotEmpty ? u.displayName : u.username,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (u.kycApproved) const VerifiedBadge(size: 14),
              if (u.username.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'seller',
                    style: TextStyle(fontSize: 10, color: cs.primary, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (u.username.isNotEmpty)
                Text('@${u.username}',
                    style: TextStyle(fontSize: 12, color: cs.primary)),
              if (u.location.isNotEmpty)
                Row(
                  children: [
                    Icon(Icons.location_on, size: 12, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        u.location,
                        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: () {
            context.push('${AppRoutes.publicProfile}/${u.uid}',
                extra: u.displayName);
          },
        );
      },
    );
  }
}
