import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../extensions/context_tr.dart';
import '../../services/follow_service.dart';
import '../../services/suggestion_service.dart';
import '../../services/user_service.dart';
import '../../widgets/ds/ds.dart';
import '../../widgets/ds/ds_follow_button.dart';

/// Followers / Following lists with search, relationship states and a
/// suggestions section. All data comes from FollowService streams.
class FollowListScreen extends StatefulWidget {
  final String userId;
  final int initialTab;

  const FollowListScreen({
    super.key,
    required this.userId,
    this.initialTab = 0,
  });

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen>
    with SingleTickerProviderStateMixin {
  final FollowService _follow = FollowService();
  final UserService _users = UserService();
  final SuggestionService _suggest = SuggestionService();
  late final TabController _tabs;
  String _query = '';
  final Map<String, String> _names = {};
  final Map<String, String> _photos = {};
  List<Map<String, dynamic>>? _suggestions;
  bool _suggestionsLoading = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
        length: 2,
        vsync: this,
        initialIndex: widget.initialTab == 1 ? 1 : 0);
    _tabs.addListener(() {
      if (_tabs.index == 1) _loadSuggestions();
    });
    if (widget.initialTab == 1) _loadSuggestions();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestions() async {
    if (_suggestionsLoading) return;
    _suggestionsLoading = true;
    try {
      final list = await _suggest.suggestSellers(limit: 5);
      if (mounted) setState(() => _suggestions = list);
    } catch (_) {
      if (mounted) setState(() => _suggestions = []);
    } finally {
      _suggestionsLoading = false;
    }
  }

  Future<void> _fillNames(List<Map<String, dynamic>> rows) async {
    final missing = rows
        .map((e) => (e['id'] ?? e['userId']).toString())
        .where((id) => id.isNotEmpty && !_names.containsKey(id))
        .toSet();
    if (missing.isEmpty) return;
    final profiles = await _users.getProfiles(missing.toList());
    if (!mounted) return;
    setState(() {
      for (final entry in profiles.entries) {
        _names[entry.key] = entry.value.displayName;
        _photos[entry.key] = entry.value.profileImage;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser?.uid ?? '';
    final mine = me.isNotEmpty && me == widget.userId;
    return Scaffold(
      appBar: AppBar(
        title: Text(mine
            ? context.tr('your_connections', 'Your connections')
            : context.tr('connections', 'Connections')),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: context.tr('followers', 'Followers')),
            Tab(text: context.tr('following', 'Following')),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              onChanged: (v) =>
                  setState(() => _query = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: context.tr('search_users', 'Tafuta mtumiaji...'),
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _listTab(isFollowers: true),
                _listTab(isFollowers: false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _listTab({required bool isFollowers}) {
    final stream = isFollowers
        ? _follow.getFollowers(widget.userId)
        : _follow.getFollowing(widget.userId);
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return DsEmptyState(
            icon: Icons.error_outline,
            title: context.tr('please_try_again'),
            actionLabel: 'Try Again',
            onAction: () => setState(() {}),
          );
        }
        var rows = snap.data ?? [];
        if (_query.isNotEmpty) {
          rows = rows.where((e) {
            final name = (_names[(e['id'] ?? e['userId']).toString()] ?? '')
                .toLowerCase();
            return name.contains(_query);
          }).toList();
        }
        if (rows.isEmpty && _query.isEmpty) {
          return DsEmptyState(
            icon: Icons.people_outline,
            title: isFollowers
                ? context.tr('no_followers_yet', 'No followers yet.')
                : context.tr(
                    'not_following_anyone', 'Not following anyone yet.'),
          );
        }
        _fillNames(rows);
        return ListView.builder(
          itemCount:
              rows.length + (!isFollowers ? 1 : 0),
          itemBuilder: (context, i) {
            if (!isFollowers && i == rows.length) {
              return _suggestionsSection();
            }
            final id =
                (rows[i]['id'] ?? rows[i]['userId']).toString();
            if (id.isEmpty) return const SizedBox.shrink();
            final name = _names[id] ?? 'Member';
            final photo = _photos[id] ?? '';
            return ListTile(
              leading: DsAvatar(
                imageUrl: photo.isEmpty ? null : photo,
                initials: name.isNotEmpty
                    ? name.characters.first.toUpperCase()
                    : '?',
              ),
              title: Text(name,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: DsFollowButton(userId: id, compact: true),
            );
          },
        );
      },
    );
  }

  Widget _suggestionsSection() {
    if (_suggestions == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_suggestions!.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr(
                'more_people_you_may_like', 'More people you may like'),
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 8),
          ..._suggestions!.map((s) {
            final id = (s['sellerId'] ?? '').toString();
            final name = (s['sellerName'] ?? 'Seller').toString();
            final product = (s['productName'] ?? '').toString();
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: DsAvatar(
                initials: name.isNotEmpty
                    ? name.characters.first.toUpperCase()
                    : '?',
              ),
              title: Text(name,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: product.isNotEmpty
                  ? Text(product,
                      maxLines: 1, overflow: TextOverflow.ellipsis)
                  : null,
              trailing:
                  DsFollowButton(userId: id, compact: true),
            );
          }),
        ],
      ),
    );
  }
}
