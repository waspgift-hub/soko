import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/group_service.dart';
import '../../services/user_service.dart';
import '../../models/group_model.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';
import '../../widgets/google_loading.dart';

class GroupChatScreen extends StatefulWidget {
  final String groupId;

  const GroupChatScreen({super.key, required this.groupId});

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final _messageController = TextEditingController();
  final _groupService = GroupService();
  final ScrollController _scrollController = ScrollController();
  GroupChat? _group;
  bool _loadingOlder = false;

  @override
  void initState() {
    super.initState();
    _loadGroup();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_loadingOlder) {
      _loadOlderMessages();
    }
  }

  Future<void> _loadGroup() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection("groups")
          .doc(widget.groupId)
          .get();
      if (doc.exists && mounted) {
        setState(() => _group = GroupChat.fromFirestore(doc));
      }
    } catch (_) {}
  }

  Future<void> _loadOlderMessages() async {
    setState(() => _loadingOlder = true);
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) setState(() => _loadingOlder = false);
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;
    try {
      await _groupService.sendMessage(
        groupId: widget.groupId,
        content: _messageController.text.trim(),
      );
      _messageController.clear();
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.tr('error')}: $e')),
        );
      }
    }
  }

  Future<void> _sendImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1200, maxHeight: 1200);
    if (image == null || !mounted) return;

    try {
      await _groupService.sendImageMessage(
        groupId: widget.groupId,
        imageUrl: image.path,
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.tr('error')}: $e')),
        );
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _showGroupInfo() {
    final user = FirebaseAuth.instance.currentUser;
    if (_group == null || user == null) return;
    final isAdmin = _group!.adminIds.contains(user.uid);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollCtrl) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
                    backgroundImage: _group!.imageUrl.isNotEmpty
                        ? NetworkImage(_group!.imageUrl)
                        : null,
                    child: _group!.imageUrl.isEmpty
                        ? const Icon(Icons.group, color: Colors.white, size: 30)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_group!.name,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        if (_group!.description.isNotEmpty)
                          Text(_group!.description,
                            style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('${_group!.participantIds.length} ${context.tr('members')}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .where(FieldPath.documentId,
                          whereIn: _group!.participantIds.take(10).toList())
                      .snapshots(),
                  builder: (context, snap) {
                    if (!snap.hasData) return const SizedBox.shrink();
                    final users = {
                      for (var d in snap.data!.docs)
                        d.id: d.data() as Map<String, dynamic>
                    };
                    return ListView.builder(
                      controller: scrollCtrl,
                      itemCount: _group!.participantIds.length,
                      itemBuilder: (_, i) {
                        final uid = _group!.participantIds[i];
                        final data = users[uid];
                        final name = data?['displayName'] as String? ?? uid;
                        final isMe = uid == user.uid;
                        final isMemberAdmin = _group!.adminIds.contains(uid);
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundImage: (data?['profileImage'] as String?)?.isNotEmpty == true
                                ? NetworkImage(data!['profileImage'])
                                : null,
                            child: (data?['profileImage'] as String?)?.isNotEmpty != true
                                ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                                    style: const TextStyle(color: Colors.white, fontSize: 14))
                                : null,
                          ),
                          title: Row(
                            children: [
                              Expanded(child: Text(name, style: const TextStyle(fontSize: 14))),
                              if (isMemberAdmin)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.amber[100],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text('Admin',
                                    style: TextStyle(fontSize: 10, color: Colors.amber[800], fontWeight: FontWeight.bold)),
                                ),
                              if (isMe)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green[100],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text('You',
                                    style: TextStyle(fontSize: 10, color: Colors.green[800], fontWeight: FontWeight.bold)),
                                ),
                            ],
                          ),
                          trailing: isAdmin && !isMe
                              ? PopupMenuButton<String>(
                                  onSelected: (val) async {
                                    if (val == 'remove') {
                                      await _groupService.removeMember(widget.groupId, uid);
                                      _loadGroup();
                                    } else if (val == 'admin') {
                                      if (isMemberAdmin) {
                                        await _groupService.removeAdmin(widget.groupId, uid);
                                      } else {
                                        await _groupService.makeAdmin(widget.groupId, uid);
                                      }
                                      _loadGroup();
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    PopupMenuItem(value: 'admin',
                                      child: Text(isMemberAdmin ? 'Remove admin' : 'Make admin')),
                                    const PopupMenuItem(value: 'remove',
                                      child: Text('Remove from group', style: TextStyle(color: Colors.red))),
                                  ],
                                )
                              : null,
                        );
                      },
                    );
                  },
                ),
              ),
              const Divider(),
              if (isAdmin)
                ListTile(
                  leading: const Icon(Icons.person_add),
                  title: Text(context.tr('add_member')),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showAddMemberDialog();
                  },
                ),
              ListTile(
                leading: const Icon(Icons.exit_to_app, color: Colors.red),
                title: Text(context.tr('leave_group'), style: const TextStyle(color: Colors.red)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: Text(context.tr('leave_group')),
                      content: const Text('Are you sure you want to leave this group?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel')),
                        TextButton(onPressed: () => Navigator.pop(context, true),
                          child: const Text('Leave', style: TextStyle(color: Colors.red))),
                      ],
                    ),
                  );
                  if (confirm == true && mounted) {
                    await _groupService.leaveGroup(widget.groupId, user.uid);
                    if (mounted) {
                      context.pop();
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddMemberDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _AddMemberDialog(groupId: widget.groupId, groupService: _groupService),
    ).then((_) => _loadGroup());
  }

  void _startGroupCall(String type) {
    if (_group == null) return;
    context.push(
      '${AppRoutes.videoCall}/${widget.groupId}',
      extra: {
        'isAudioOnly': type != 'video',
        'callId': '',
        'remoteName': _group!.name,
        'remoteImage': '',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: _group != null
            ? GestureDetector(
                onTap: () => _showGroupInfo(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_group!.name),
                    if (_group!.description.isNotEmpty)
                      Text(_group!.description,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.6))),
                    Text('${_group!.participantIds.length} ${context.tr('members')}',
                      style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.7))),
                  ],
                ),
              )
            : const Text(''),
        actions: [
          IconButton(
            icon: const Icon(Icons.call),
            tooltip: context.tr('voice_call'),
            onPressed: _group != null ? () => _startGroupCall('voice') : null,
          ),
          IconButton(
            icon: const Icon(Icons.videocam),
            tooltip: context.tr('video_call'),
            onPressed: _group != null ? () => _startGroupCall('video') : null,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessagesList(user, cs)),
          _buildInputArea(cs),
        ],
      ),
    );
  }

  Widget _buildMessagesList(User? user, ColorScheme cs) {
    return StreamBuilder<List<GroupMessage>>(
      stream: _groupService.getMessages(widget.groupId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('${context.tr('error')}: ${snapshot.error}',
                textAlign: TextAlign.center, style: TextStyle(color: cs.error)),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const GoogleLoadingPage();
        }
        final messages = snapshot.data ?? [];
        if (messages.isEmpty) {
          return Center(
            child: Text(context.tr('no_messages_yet'),
              style: TextStyle(color: cs.onSurface.withOpacity(0.6))),
          );
        }
        return Column(
          children: [
            if (_loadingOlder)
              const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(10),
                reverse: true,
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final message = messages[index];
                  final isMe = message.senderId == user?.uid;
                  if (message.isSystem) {
                    return _buildSystemMessage(message, cs);
                  }
                  return _buildMessageBubble(message, isMe, cs);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSystemMessage(GroupMessage message, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withOpacity(0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(message.content,
            style: TextStyle(color: cs.onSurface.withOpacity(0.6), fontSize: 12)),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(GroupMessage message, bool isMe, ColorScheme cs) {
    if (message.type == 'image') {
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
              bottomRight: isMe ? Radius.zero : const Radius.circular(16),
            ),
            color: isMe ? cs.primary : cs.surface,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMe)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Text(message.senderName,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.primary)),
                ),
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.zero, bottom: Radius.circular(16)),
                child: Image.network(message.content,
                  fit: BoxFit.cover, width: double.infinity,
                  loadingBuilder: (ctx, child, progress) => progress == null
                      ? child
                      : const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
                  errorBuilder: (context, error, stackTrace) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Failed to load image',
                      style: TextStyle(color: isMe ? Colors.white70 : cs.onSurface.withOpacity(0.6))),
                  )),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                child: Text(
                  '${message.timestamp.hour}:${message.timestamp.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(fontSize: 11,
                    color: isMe ? Colors.white70 : cs.onSurface.withOpacity(0.6)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          gradient: isMe
              ? LinearGradient(colors: [cs.primary, cs.primary.withOpacity(0.8)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight)
              : null,
          color: isMe ? null : cs.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
            bottomRight: isMe ? Radius.zero : const Radius.circular(16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(message.senderName,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.primary)),
              ),
            Text(message.content,
              style: TextStyle(fontSize: 16, color: isMe ? Colors.white : cs.onSurface)),
            const SizedBox(height: 4),
            Text(
              '${message.timestamp.hour}:${message.timestamp.minute.toString().padLeft(2, '0')}',
              style: TextStyle(fontSize: 11,
                color: isMe ? Colors.white70 : cs.onSurface.withOpacity(0.6)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: cs.surface,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.image, size: 24),
            color: cs.primary,
            onPressed: _sendImage,
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: context.tr('type_message'),
                  hintStyle: TextStyle(color: cs.onSurface.withOpacity(0.4)),
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [cs.primary, cs.primary.withOpacity(0.8)]),
              shape: BoxShape.circle,
            ),
            child: FloatingActionButton(
              onPressed: _sendMessage,
              backgroundColor: Colors.transparent,
              elevation: 0,
              mini: true,
              child: const Icon(Icons.send, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddMemberDialog extends StatefulWidget {
  final String groupId;
  final GroupService groupService;
  const _AddMemberDialog({required this.groupId, required this.groupService});

  @override
  State<_AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<_AddMemberDialog> {
  final _searchController = TextEditingController();
  final _userService = UserService();
  List<UserProfile> _allUsers = [];
  List<UserProfile> _filteredUsers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _searchController.addListener(_filterUsers);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    try {
      final users = await _userService.searchUsers('');
      final groupDoc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .get();
      final participantIds = List<String>.from(groupDoc.data()?['participantIds'] ?? []);
      if (mounted) {
        setState(() {
          _allUsers = users.where((u) => !participantIds.contains(u.uid)).toList();
          _filteredUsers = _allUsers;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _filterUsers() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filteredUsers = query.isEmpty
          ? _allUsers
          : _allUsers.where((u) {
              final name = u.displayName.toLowerCase();
              final username = u.username.toLowerCase();
              return name.contains(query) || username.contains(query);
            }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Member'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: context.tr('search_users'),
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            _loading
                ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()))
                : _filteredUsers.isEmpty
                    ? Text(context.tr('no_users_found'))
                    : SizedBox(
                        height: 300,
                        child: ListView.builder(
                          itemCount: _filteredUsers.length,
                          itemBuilder: (_, i) {
                            final user = _filteredUsers[i];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundImage: user.profileImage.isNotEmpty
                                    ? NetworkImage(user.profileImage)
                                    : null,
                                child: user.profileImage.isEmpty
                                    ? Text(user.displayName.isNotEmpty
                                        ? user.displayName[0].toUpperCase() : '?')
                                    : null,
                              ),
                              title: Text(user.displayName.isNotEmpty ? user.displayName : user.uid),
                              subtitle: user.username.isNotEmpty ? Text('@${user.username}') : null,
                              trailing: const Icon(Icons.add),
                              onTap: () async {
                                final currentUser = FirebaseAuth.instance.currentUser;
                                await widget.groupService.addMemberWithMessage(
                                  widget.groupId,
                                  user.uid,
                                  currentUser?.displayName ?? 'Someone',
                                );
                                if (mounted) Navigator.pop(context);
                              },
                            );
                          },
                        ),
                      ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}

