import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/chat_service.dart';
import '../../services/user_service.dart';
import '../../services/whatsapp_service.dart';
import '../../models/message_model.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';

class ChatsListScreen extends StatefulWidget {
  const ChatsListScreen({super.key});

  @override
  State<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends State<ChatsListScreen> {
  final ChatService _chatService = ChatService();
  final _searchCtrl = TextEditingController();
  List<Conversation> _allConvs = [];
  List<Conversation> _filtered = [];
  String? _currentUid;

  @override
  void initState() {
    super.initState();
    _currentUid = FirebaseAuth.instance.currentUser?.uid;
    _searchCtrl.addListener(_filter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _filter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _allConvs
          : _allConvs.where((c) {
              final otherId =
                  c.participants.where((p) => p != _currentUid).firstOrNull ?? '';
              final name = c.participantNames[otherId] ?? '';
              return name.toLowerCase().contains(q);
            }).toList();
    });
  }

  String _otherParticipantId(Conversation c) =>
      c.participants.where((p) => p != _currentUid).firstOrNull ?? '';

  String _otherParticipantName(Conversation c) {
    final id = _otherParticipantId(c);
    return c.participantNames[id] ?? id;
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sorted = List<Conversation>.from(_filtered)
      ..sort((a, b) {
        if (a.isPinned && !b.isPinned) return -1;
        if (!a.isPinned && b.isPinned) return 1;
        return b.lastMessageTime.compareTo(a.lastMessageTime);
      });

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('messages')),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: context.tr('new_message'),
            onPressed: _showNewChat,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        mini: true,
        onPressed: _showNewChat,
        child: const Icon(Icons.chat),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: context.tr('search'),
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Conversation>>(
              stream: _chatService.getConversations(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final convs = snap.data ?? [];
                if (convs != _allConvs) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      _allConvs = convs;
                      _filter();
                    }
                  });
                }
                if (convs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_bubble_outline,
                            size: 64, color: cs.outline),
                        const SizedBox(height: 16),
                        Text(context.tr('no_conversations'),
                            style: TextStyle(color: cs.onSurfaceVariant)),
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async {},
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: sorted.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
                    itemBuilder: (_, i) {
                      final c = sorted[i];
                      final otherId = _otherParticipantId(c);
                      final name = _otherParticipantName(c);
                      final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

                      return Dismissible(
                        key: ValueKey(c.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          color: cs.error,
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) =>
                            _chatService.deleteConversation(otherId),
                        child: ListTile(
                          leading: Stack(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: cs.primaryContainer,
                                child: Text(initial,
                                    style: TextStyle(
                                        color: cs.onPrimaryContainer,
                                        fontWeight: FontWeight.bold)),
                              ),
                              if (c.isMuted)
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: cs.surface,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(Icons.volume_off,
                                        size: 12, color: cs.outline),
                                  ),
                                ),
                            ],
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                              ),
                              if (c.isPinned)
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Icon(Icons.push_pin,
                                      size: 14, color: cs.outline),
                                ),
                              Text(
                                _formatTime(c.lastMessageTime),
                                style: TextStyle(
                                    fontSize: 12, color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                          subtitle: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  c.lastMessage,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: c.unreadCount > 0
                                        ? cs.onSurface
                                        : cs.onSurfaceVariant,
                                    fontWeight: c.unreadCount > 0
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                              if (c.unreadCount > 0)
                                Container(
                                  margin: const EdgeInsets.only(left: 8),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: cs.primary,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    c.unreadCount > 99
                                        ? '99+'
                                        : '${c.unreadCount}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                            ],
                          ),
                          onTap: () {
                            _chatService.markAsRead(otherId);
                            context.push('${AppRoutes.chat}/$otherId',
                                extra: {'name': name});
                          },
                          onLongPress: () => _showOptions(c, otherId, name),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showOptions(Conversation c, String otherId, String name) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(c.isPinned ? Icons.push_pin : Icons.push_pin_outlined),
              title: Text(c.isPinned ? 'Unpin' : 'Pin'),
              onTap: () {
                Navigator.pop(ctx);
                if (c.isPinned) {
                  _chatService.unpinConversation(otherId);
                } else {
                  _chatService.pinConversation(otherId);
                }
              },
            ),
            ListTile(
              leading: Icon(c.isMuted ? Icons.volume_up : Icons.volume_off),
              title: Text(c.isMuted ? 'Unmute' : 'Mute'),
              onTap: () {
                Navigator.pop(ctx);
                if (c.isMuted) {
                  _chatService.unmuteConversation(otherId);
                } else {
                  _chatService.muteConversation(otherId);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.person),
              title: Text(context.tr('view_profile')),
              onTap: () {
                Navigator.pop(ctx);
                context.push('${AppRoutes.publicProfile}/$otherId',
                    extra: name);
              },
            ),
            ListTile(
              leading: const Icon(Icons.chat, color: Color(0xFF25D366)),
              title: const Text('WhatsApp'),
              onTap: () {
                Navigator.pop(ctx);
                _openWhatsApp(otherId, name);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete, color: cs.error),
              title: Text(context.tr('delete'),
                  style: TextStyle(color: cs.error)),
              onTap: () {
                Navigator.pop(ctx);
                _chatService.deleteConversation(otherId);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openWhatsApp(String otherId, String name) async {
    final profile = await UserService().getProfile(otherId);
    if (profile == null || profile.phone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('phone_not_found'))),
        );
      }
      return;
    }
    final msg = WhatsAppService.generateProfileMessage(sellerName: name);
    WhatsAppService().openWhatsApp(phoneNumber: profile.phone, message: msg);
  }

  void _showNewChat() async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final snap = await FirebaseFirestore.instance.collection('users').get();
    if (!mounted) return;
    final users = snap.docs
        .map((doc) => UserProfile.fromMap(doc.id, doc.data()))
        .where((u) => u.uid != currentUid)
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _NewChatSheet(users: users),
    );
  }

  ColorScheme get cs => Theme.of(context).colorScheme;
}

class _NewChatSheet extends StatefulWidget {
  final List<UserProfile> users;
  const _NewChatSheet({required this.users});

  @override
  State<_NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends State<_NewChatSheet> {
  final _searchCtrl = TextEditingController();
  late List<UserProfile> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = widget.users;
    _searchCtrl.addListener(_filter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _filter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? widget.users
          : widget.users
              .where((u) =>
                  u.displayName.toLowerCase().contains(q) ||
                  u.username.toLowerCase().contains(q))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      expand: false,
      builder: (context, scrollCtrl) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          children: [
            // Handle
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(context.tr('new_message'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: context.tr('search_users'),
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _filtered.isEmpty
                  ? Center(
                      child: Text(context.tr('no_users_found'),
                          style: TextStyle(color: cs.onSurfaceVariant)),
                    )
                  : ListView.builder(
                      controller: scrollCtrl,
                      itemCount: _filtered.length,
                      itemBuilder: (_, i) {
                        final user = _filtered[i];
                        final initial = user.displayName.isNotEmpty
                            ? user.displayName[0].toUpperCase()
                            : '?';
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: cs.primaryContainer,
                            backgroundImage: user.profileImage.isNotEmpty
                                ? NetworkImage(user.profileImage)
                                : null,
                            child: user.profileImage.isEmpty
                                ? Text(initial,
                                    style: TextStyle(
                                        color: cs.onPrimaryContainer,
                                        fontWeight: FontWeight.bold))
                                : null,
                          ),
                          title: Text(user.displayName),
                          subtitle: user.username.isNotEmpty
                              ? Text('@${user.username}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: cs.onSurfaceVariant))
                              : null,
                          onTap: () {
                            Navigator.pop(context);
                            context.push('${AppRoutes.chat}/${user.uid}',
                                extra: {'name': user.displayName});
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
