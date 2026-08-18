import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/chat_service.dart';
import '../../services/user_service.dart';
import '../../services/local_cache_service.dart';
import '../../services/shortcut_service.dart';
import '../../models/chat_room.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/verified_badge.dart';
import '../../widgets/ds/ds.dart';
import '../../widgets/soko_vibe_states.dart';

class ChatInboxScreen extends StatefulWidget {
  const ChatInboxScreen({super.key});

  @override
  State<ChatInboxScreen> createState() => _ChatInboxScreenState();
}

class _ChatInboxScreenState extends State<ChatInboxScreen> {
  final ChatService _chatService = ChatService();
  final UserService _userService = UserService();
  final Map<String, String> _userNames = {};
  final Map<String, String> _userPhotos = {};
  final Map<String, bool> _userKyc = {};
  int _activeTab = 0;
  bool _selectMode = false;
  final Set<String> _selectedIds = {};
  Set<String> _hiddenUsers = {};
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadCached();
    _loadHiddenUsers();
  }

  Future<void> _loadHiddenUsers() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = snap.data();
    if (data != null && mounted) {
      final list = data['hidden_users'];
      if (list is List) {
        setState(() => _hiddenUsers = list.cast<String>().toSet());
      }
    }
  }

  void _loadCached() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final cached = LocalCacheService.getCachedRoomsForUser(uid);
    for (final room in cached) {
      final otherId = room.participants.where((p) => p != uid).firstOrNull;
      if (otherId != null) _fetchUser(otherId);
    }
  }

  Future<void> _fetchUser(String uid) async {
    if (_userNames.containsKey(uid)) return;
    final profile = await _userService.getProfile(uid);
    if (profile != null && mounted) {
      setState(() {
        _userNames[uid] = profile.displayName;
        _userPhotos[uid] = profile.profileImage;
        _userKyc[uid] = profile.kycApproved;
      });
    }
  }

  void _toggleSelect(String roomId) {
    setState(() {
      if (_selectedIds.contains(roomId)) {
        _selectedIds.remove(roomId);
        if (_selectedIds.isEmpty) _selectMode = false;
      } else {
        _selectedIds.add(roomId);
      }
    });
  }

  void _selectAll(List<ChatRoom> rooms) {
    setState(() {
      if (_selectedIds.length == rooms.length) {
        _selectedIds.clear();
        _selectMode = false;
      } else {
        _selectedIds.addAll(rooms.map((r) => r.id));
      }
    });
  }

  void _exitSelectMode() {
    setState(() {
      _selectMode = false;
      _selectedIds.clear();
    });
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.primary,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showConfirmDialog({
    required String title,
    required String content,
    required VoidCallback onConfirm,
    bool isDestructive = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('cancel')),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
            child: Text(
              context.tr('confirm'),
              style: TextStyle(color: isDestructive ? cs.error : cs.primary),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: _selectMode
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitSelectMode,
              ),
              title: Text('${_selectedIds.length}'),
              backgroundColor: Colors.transparent,
              elevation: 0,
              actions: [
                IconButton(
                  icon: const Icon(Icons.select_all),
                  tooltip: context.tr('select_all'),
                  onPressed: () {
                    final allRooms = (_chatService.getRooms()) as dynamic;
                    // We need the full list; use StreamBuilder's data
                    _selectAllFromStream();
                  },
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (action) => _batchAction(action),
                  itemBuilder: (ctx) => [
                    PopupMenuItem(value: 'mark_read', child: Text(context.tr('mark_all_read'))),
                    PopupMenuItem(value: 'mute', child: Text(context.tr('mute'))),
                    PopupMenuItem(value: 'unmute', child: Text(context.tr('unmute'))),
                    PopupMenuItem(value: 'archive', child: Text(context.tr('archive'))),
                    PopupMenuItem(value: 'delete', child: Text(context.tr('delete_conversations'), style: TextStyle(color: cs.error))),
                  ],
                ),
              ],
            )
          : AppBar(
              title: Text(context.tr('chats', 'Chats')),
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
      body: Column(
        children: [
          if (!_selectMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: TextField(
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: context.tr('search_users', 'Tafuta mtumiaji...'),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
          if (!_selectMode)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  _buildTabChip(context, context.tr('all', 'All'), 0),
                  const SizedBox(width: 6),
                  _buildTabChip(context, context.tr('unread', 'Unread'), 1),
                  const SizedBox(width: 6),
                  _buildTabChip(context, context.tr('favourited', 'Favourite'), 2),
                  const SizedBox(width: 6),
                  _buildTabChip(context, context.tr('archived', 'Archive'), 3),
                ],
              ),
            ),
          Expanded(
            child: StreamBuilder<List<ChatRoom>>(
              stream: _chatService.getRooms(),
              builder: (context, snap) {
                final allRooms = snap.data ?? [];
                final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

                final rooms = allRooms.where((r) {
                  final otherId = r.participants.where((p) => p != myUid).firstOrNull ?? '';

                  if (_searchQuery.isNotEmpty) {
                    final name = _userNames[otherId]?.toLowerCase() ?? '';
                    return name.contains(_searchQuery.toLowerCase());
                  }

                  if (_hiddenUsers.contains(otherId)) return false;

                  switch (_activeTab) {
                    case 1:
                      return r.unreadCountFor(myUid) > 0 && !r.archivedBy.contains(myUid);
                    case 2:
                      return r.isFavourited(myUid) && !r.archivedBy.contains(myUid);
                    case 3:
                      return r.archivedBy.contains(myUid);
                    default:
                      return !r.archivedBy.contains(myUid);
                  }
                }).toList();

                // Sort: favourited first, then pinned, then by timestamp
                rooms.sort((a, b) {
                  final aFav = a.isFavourited(myUid) ? 1 : 0;
                  final bFav = b.isFavourited(myUid) ? 1 : 0;
                  if (aFav != bFav) return bFav - aFav;
                  final aPin = a.isPinned(myUid) ? 1 : 0;
                  final bPin = b.isPinned(myUid) ? 1 : 0;
                  if (aPin != bPin) return bPin - aPin;
                  return (b.lastTimestamp?.millisecondsSinceEpoch ?? 0)
                      .compareTo(a.lastTimestamp?.millisecondsSinceEpoch ?? 0);
                });

                if (!snap.hasData) {
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                    itemCount: 8,
                    itemBuilder: (context, _) => const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          DsSkeleton(shape: DsSkeletonShape.circle, width: 52, height: 52),
                          SizedBox(width: 14),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DsSkeleton(width: 140, height: 14),
                              SizedBox(height: 8),
                              DsSkeleton(width: double.infinity, height: 12),
                            ],
                          )),
                        ],
                      ),
                    ),
                  );
                }
                if (rooms.isEmpty) {
                  return SokoVibeEmptyState(
                    icon: Icons.chat_bubble_outline,
                    title: context.tr('no_conversations', 'No conversations yet'),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                  itemCount: rooms.length,
                  itemBuilder: (_, i) {
                    final room = rooms[i];
                    final otherId = room.participants.where((p) => p != myUid).firstOrNull ?? '';
                    if (otherId.isEmpty) return const SizedBox.shrink();
                    _fetchUser(otherId);
                    final name = _userNames[otherId] ?? context.tr('member', 'Member');
                    final photo = _userPhotos[otherId] ?? '';
                    final unreadCount = room.unreadCountFor(myUid);

                    return _ChatListTile(
                      name: name,
                      photo: photo,
                      kycApproved: _userKyc[otherId] ?? false,
                      lastMessage: room.lastMessage,
                      lastTimestamp: room.lastTimestamp,
                      unreadCount: unreadCount,
                      isPinned: room.isPinned(myUid),
                      isMuted: room.isMuted(myUid),
                      isFavourited: room.isFavourited(myUid),
                      isArchived: room.isArchived(myUid),
                      isSelected: _selectedIds.contains(room.id),
                      selectMode: _selectMode,
                      onTap: () {
                        if (_selectMode) {
                          _toggleSelect(room.id);
                        } else {
                          _openChat(otherId, room);
                        }
                      },
                      onLongPress: () {
                        if (!_selectMode) {
                          setState(() => _selectMode = true);
                          _toggleSelect(room.id);
                        }
                      },
                      onMenuAction: (action) => _handleMenuAction(action, room, otherId, name),
                      cs: cs,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _selectAllFromStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _chatService.getRooms().first.then((rooms) {
      if (!mounted) return;
      final visible = rooms.where((r) {
        final otherId = r.participants.where((p) => p != uid).firstOrNull ?? '';
        if (_hiddenUsers.contains(otherId)) return false;
        switch (_activeTab) {
          case 1:
            return r.unreadCountFor(uid) > 0 && !r.archivedBy.contains(uid);
          case 2:
            return r.isFavourited(uid) && !r.archivedBy.contains(uid);
          case 3:
            return r.archivedBy.contains(uid);
          default:
            return !r.archivedBy.contains(uid);
        }
      }).toList();
      setState(() {
        _selectedIds.addAll(visible.map((r) => r.id));
      });
    });
  }

  Future<void> _openChat(String otherId, ChatRoom room) async {
    await _chatService.getOrCreateRoom(otherUserId: otherId);
    if (context.mounted) {
      context.push('/chat/$otherId', extra: {
        'name': _userNames[otherId] ?? '',
        'productId': room.productId ?? '',
        'productTitle': room.productTitle ?? '',
      });
    }
  }

  void _handleMenuAction(String action, ChatRoom room, String otherId, String name) async {
    final cs = Theme.of(context).colorScheme;
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    switch (action) {
      case 'select':
        if (!_selectMode) setState(() => _selectMode = true);
        _toggleSelect(room.id);
        break;
      case 'delete_conversation':
        _showConfirmDialog(
          title: context.tr('delete_conversation'),
          content: context.tr('delete_conversation_confirm', name),
          onConfirm: () async {
            await _chatService.deleteAllMessages(room.id);
            await _chatService.deleteForMe(room.id);
            _showSnack(context.tr('conversation_deleted'));
          },
          isDestructive: true,
        );
        break;
      case 'delete_user':
        _showConfirmDialog(
          title: context.tr('delete_user'),
          content: context.tr('delete_user_confirm', name),
          onConfirm: () async {
            final myUid = FirebaseAuth.instance.currentUser?.uid;
            if (myUid == null) return;
            await FirebaseFirestore.instance.collection('users').doc(myUid).update({
              'hidden_users': FieldValue.arrayUnion([otherId]),
            });
            setState(() => _hiddenUsers.add(otherId));
            _showSnack(context.tr('user_hidden', 'Mtumiaji amefichwa'));
          },
          isDestructive: true,
        );
        break;
      case 'block':
        _showConfirmDialog(
          title: context.tr('block_user'),
          content: context.tr('block_user_confirm', name),
          onConfirm: () async {
            await _chatService.blockUser(otherId);
            _showSnack(context.tr('user_blocked'));
          },
          isDestructive: true,
        );
        break;
      case 'mute':
        await _chatService.toggleMute(room.id);
        _showSnack(room.isMuted(myUid) ? context.tr('muted') : context.tr('unmuted'));
        if (mounted) setState(() {});
        break;
      case 'unmute':
        await _chatService.toggleMute(room.id);
        _showSnack(context.tr('unmuted'));
        if (mounted) setState(() {});
        break;
      case 'pin':
        await _chatService.togglePin(room.id);
        _showSnack(room.isPinned(myUid) ? context.tr('unpinned') : context.tr('pinned'));
        if (mounted) setState(() {});
        break;
      case 'archive':
        await _chatService.toggleArchive(room.id);
        _showSnack(room.isArchived(myUid) ? context.tr('archived') : context.tr('unarchived'));
        if (mounted) setState(() {});
        break;
      case 'shortcut':
        final pinned = await pinChatShortcut(
          receiverId: otherId,
          receiverName: name,
        );
        _showSnack(pinned
            ? context.tr('shortcut_added')
            : context.tr('shortcut_not_supported', 'Shortcut haijaungana kwenye skrini ya nyumbani'));
        break;
      case 'view_profile':
        if (context.mounted) {
          context.push('/profile/$otherId');
        }
        break;
      case 'mark_read':
        await _chatService.markAsRead(room.id);
        _showSnack(context.tr('marked_as_read'));
        if (mounted) setState(() {});
        break;
      case 'favourite':
        await _chatService.toggleFavourite(room.id);
        _showSnack(room.isFavourited(myUid) ? context.tr('removed_from_favourites') : context.tr('added_to_favourites'));
        if (mounted) setState(() {});
        break;
    }
  }

  void _batchAction(String action) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    for (final roomId in _selectedIds) {
      switch (action) {
        case 'mark_read':
          await _chatService.markAsRead(roomId);
          break;
        case 'mute':
          final doc = await _chatService.getRoomDoc(roomId);
          if (doc != null && !doc.isMuted(myUid)) {
            await _chatService.toggleMute(roomId);
          }
          break;
        case 'unmute':
          final doc = await _chatService.getRoomDoc(roomId);
          if (doc != null && doc.isMuted(myUid)) {
            await _chatService.toggleMute(roomId);
          }
          break;
        case 'archive':
          await _chatService.toggleArchive(roomId);
          break;
        case 'delete':
          await _chatService.deleteAllMessages(roomId);
          await _chatService.deleteForMe(roomId);
          break;
      }
    }
    _exitSelectMode();
    _showSnack(context.tr('action_completed'));
  }

  Widget _buildTabChip(BuildContext context, String label, int index) {
    final cs = Theme.of(context).colorScheme;
    final selected = _activeTab == index;
    return GestureDetector(
      onTap: () => setState(() {
        _activeTab = index;
        _searchQuery = '';
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? cs.surface : cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _ChatListTile extends StatelessWidget {
  final String name;
  final String photo;
  final bool kycApproved;
  final String? lastMessage;
  final DateTime? lastTimestamp;
  final int unreadCount;
  final bool isPinned;
  final bool isMuted;
  final bool isFavourited;
  final bool isArchived;
  final bool isSelected;
  final bool selectMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final Function(String) onMenuAction;
  final ColorScheme cs;

  const _ChatListTile({
    required this.name,
    required this.photo,
    this.kycApproved = false,
    this.lastMessage,
    this.lastTimestamp,
    this.unreadCount = 0,
    this.isPinned = false,
    this.isMuted = false,
    this.isFavourited = false,
    this.isArchived = false,
    this.isSelected = false,
    this.selectMode = false,
    required this.onTap,
    required this.onLongPress,
    required this.onMenuAction,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: isSelected ? cs.primary.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                if (selectMode)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Icon(
                      isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: isSelected ? cs.primary : cs.onSurfaceVariant,
                      size: 24,
                    ),
                  ),
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: cs.primary.withValues(alpha: 0.12),
                      backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                      child: photo.isEmpty
                          ? Icon(Icons.person, size: 28, color: cs.primary)
                          : null,
                    ),
                    if (isPinned)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: cs.surface,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.push_pin, size: 12, color: cs.primary),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                if (isFavourited)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: Icon(Icons.favorite, size: 14, color: cs.error),
                                  ),
                                Flexible(child: Text(name, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: cs.onSurface))),
                                if (kycApproved) VerifiedBadge(size: 14),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isMuted)
                                Icon(Icons.volume_off, size: 14, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                              if (lastTimestamp != null)
                                Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Text(
                                    _formatTime(context, lastTimestamp!),
                                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              lastMessage ?? context.tr('no_messages', 'No messages'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                            ),
                          ),
                          if (unreadCount > 0 && !selectMode)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text('$unreadCount', style: TextStyle(fontSize: 11, color: cs.surface, fontWeight: FontWeight.w600)),
                            ),
                          if (!selectMode)
                            _buildMenuButton(context),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuButton(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, size: 20, color: cs.onSurfaceVariant),
      onSelected: onMenuAction,
      itemBuilder: (ctx) => [
        PopupMenuItem(value: 'select', child: Row(children: [const Icon(Icons.checklist, size: 20), const SizedBox(width: 10), Text(context.tr('select'))])),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'favourite', child: Row(children: [Icon(isFavourited ? Icons.favorite_border : Icons.favorite, size: 20), const SizedBox(width: 10), Text(isFavourited ? context.tr('remove_favourite') : context.tr('add_favourite'))])),
        PopupMenuItem(value: 'pin', child: Row(children: [Icon(isPinned ? Icons.push_pin_outlined : Icons.push_pin, size: 20), const SizedBox(width: 10), Text(isPinned ? context.tr('unpin') : context.tr('pin'))])),
        PopupMenuItem(value: isMuted ? 'unmute' : 'mute', child: Row(children: [Icon(isMuted ? Icons.volume_up : Icons.volume_off, size: 20), const SizedBox(width: 10), Text(isMuted ? context.tr('unmute') : context.tr('mute'))])),
        PopupMenuItem(value: 'archive', child: Row(children: [Icon(isArchived ? Icons.unarchive : Icons.archive, size: 20), const SizedBox(width: 10), Text(isArchived ? context.tr('unarchive') : context.tr('archive'))])),
        PopupMenuItem(value: 'mark_read', child: Row(children: [const Icon(Icons.mark_email_read_outlined, size: 20), const SizedBox(width: 10), Text(context.tr('mark_as_read'))])),
        PopupMenuItem(value: 'shortcut', child: Row(children: [const Icon(Icons.shortcut, size: 20), const SizedBox(width: 10), Text(context.tr('add_shortcut'))])),
        PopupMenuItem(value: 'view_profile', child: Row(children: [const Icon(Icons.person_outline, size: 20), const SizedBox(width: 10), Text(context.tr('view_profile'))])),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'block', child: Row(children: [Icon(Icons.block, size: 20, color: cs.error), const SizedBox(width: 10), Text(context.tr('block_user'), style: TextStyle(color: cs.error))])),
        PopupMenuItem(value: 'delete_conversation', child: Row(children: [Icon(Icons.delete_outline, size: 20, color: cs.error), const SizedBox(width: 10), Text(context.tr('delete_conversation'), style: TextStyle(color: cs.error))])),
        PopupMenuItem(value: 'delete_user', child: Row(children: [Icon(Icons.person_remove_outlined, size: 20, color: cs.error), const SizedBox(width: 10), Text(context.tr('delete_user'), style: TextStyle(color: cs.error))])),
      ],
    );
  }

  String _formatTime(BuildContext context, DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (diff.inDays == 1) return context.tr('yesterday', 'Yesterday');
    return '${dt.day}/${dt.month}';
  }
}
