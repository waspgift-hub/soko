import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/user_service.dart';
import '../../services/whatsapp_service.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/google_loading.dart';
import '../../widgets/ad_banner.dart';

class ChatsListScreen extends StatefulWidget {
  const ChatsListScreen({super.key});

  @override
  State<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends State<ChatsListScreen> {
  final _searchController = TextEditingController();
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
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      final snap = await FirebaseFirestore.instance.collection('users').get();
      if (!mounted) return;
      final users = snap.docs
          .map((doc) => UserProfile.fromMap(doc.id, doc.data()))
          .where((u) => u.uid != currentUid)
          .toList();
      users.sort((a, b) => a.displayName.compareTo(b.displayName));
      setState(() {
        _allUsers = users;
        _filteredUsers = users;
        _loading = false;
      });
    } catch (e) {
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
              final phone = u.phone.toLowerCase();
              final username = u.username.toLowerCase();
              return name.contains(query) ||
                  phone.contains(query) ||
                  username.contains(query);
            }).toList();
    });
  }

  void _openWhatsApp(UserProfile user) {
    final phone = user.phone;
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Namba ya simu haipatikani'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final message =
        'Habari ${user.displayName}, nimekuona kwenye Soko Vibe na ningependa kufanya biashara na wewe.';
    WhatsAppService().openWhatsApp(
      phoneNumber: phone,
      message: message,
      onError: () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Imeshindwa kufungua WhatsApp'),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
      onFallback: () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('WhatsApp haipo, imefungua tovuti'),
            ),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WhatsApp'),
        actions: [
          IconButton(
            icon: const Icon(Icons.group_add),
            tooltip: context.tr('create_group'),
            onPressed: () => _openWhatsAppGroup(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: context.tr('search_users'),
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const GoogleLoadingPage()
                : _filteredUsers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.people_outline,
                              size: 64,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.4),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              context.tr('no_users_found'),
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.6),
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _filteredUsers.length,
                        itemBuilder: (context, index) {
                          final user = _filteredUsers[index];
                          final initial = user.displayName.isNotEmpty
                              ? user.displayName[0].toUpperCase()
                              : '?';
                          return Card(
                            margin: const EdgeInsets.only(bottom: 6),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer,
                                backgroundImage:
                                    user.profileImage.isNotEmpty
                                        ? NetworkImage(user.profileImage)
                                        : null,
                                child: user.profileImage.isEmpty
                                    ? Text(
                                        initial,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      )
                                    : null,
                              ),
                              title: Text(
                                user.displayName.isNotEmpty
                                    ? user.displayName
                                    : user.uid,
                              ),
                              subtitle: user.phone.isNotEmpty
                                  ? Text(
                                      user.phone,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    )
                                  : null,
                              trailing: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF25D366),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.chat,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              onTap: () => _openWhatsApp(user),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      bottomNavigationBar: const AdBanner(),
    );
  }

  void _openWhatsAppGroup() {
    WhatsAppService().openWhatsApp(
      phoneNumber: '',
      message: 'Ninatengeneza kikundi cha Soko Vibe. Tafadhali niongeze.',
      onError: () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Imeshindwa kufungua WhatsApp'),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
    );
  }
}
