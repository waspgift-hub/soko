import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../../services/group_service.dart';
import '../../services/user_service.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _searchController = TextEditingController();
  final _groupService = GroupService();
  final _userService = UserService();

  List<UserProfile> _allUsers = [];
  List<UserProfile> _filteredUsers = [];
  Set<String> _selectedIds = {};
  bool _isLoading = true;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _searchController.addListener(_filterUsers);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    try {
      final users = await _userService.searchUsers('');
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (mounted) {
        setState(() {
          _allUsers = users.where((u) => u.uid != currentUid).toList();
          _filteredUsers = _allUsers;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
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

  void _toggleSelection(String uid) {
    setState(() {
      if (_selectedIds.contains(uid)) {
        _selectedIds.remove(uid);
      } else {
        _selectedIds.add(uid);
      }
    });
  }

  Future<void> _createGroup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    if (_selectedIds.isEmpty) return;

    setState(() => _isCreating = true);

    try {
      final group = await _groupService.createGroup(
        name: name,
        description: _descController.text.trim(),
        participantIds: _selectedIds.toList(),
      );
      if (mounted) {
        context.pushReplacement(
          '${AppRoutes.groupChat}/${group.id}',
          extra: group.name,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${context.tr('error')}: $e')));
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('create_group'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _nameController,
              decoration: InputDecoration(
                hintText: context.tr('group_name'),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.group),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
            child: TextField(
              controller: _descController,
              decoration: InputDecoration(
                hintText: context.tr('group_description'),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.description),
              ),
              maxLines: 2,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: context.tr('search_users'),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.search),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (_selectedIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                '${_selectedIds.length} ${context.tr('selected')}',
                style: TextStyle(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredUsers.isEmpty
                ? Center(child: Text(context.tr('no_users_found')))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _filteredUsers.length,
                    itemBuilder: (context, index) {
                      final user = _filteredUsers[index];
                      final isSelected = _selectedIds.contains(user.uid);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: cs.primaryContainer,
                            backgroundImage: user.profileImage.isNotEmpty
                                ? NetworkImage(user.profileImage)
                                : null,
                            child: user.profileImage.isEmpty
                                ? Text(
                                    user.displayName.isNotEmpty
                                        ? user.displayName[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(color: Colors.white),
                                  )
                                : null,
                          ),
                          title: Text(
                            user.displayName.isNotEmpty
                                ? user.displayName
                                : user.uid,
                          ),
                          subtitle: user.username.isNotEmpty
                              ? Text('@${user.username}')
                              : null,
                          trailing: Icon(
                            isSelected
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                            color: isSelected ? cs.primary : cs.outlineVariant,
                          ),
                          onTap: () => _toggleSelection(user.uid),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: _selectedIds.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _isCreating ? null : _createGroup,
              backgroundColor: cs.primary,
              icon: _isCreating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check, color: Colors.white),
              label: Text(
                context.tr('create'),
                style: const TextStyle(color: Colors.white),
              ),
            )
          : null,
    );
  }
}
