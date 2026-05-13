import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/notification_item.dart';
import '../../services/product_service.dart';
import '../../extensions/context_tr.dart';
import '../chat/chat_page.dart';
import '../home/product_detail.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  List<NotificationItem> _notifications = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _setupListeners();
  }

  void _setupListeners() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    FirebaseFirestore.instance
        .collection("conversations")
        .where("participants", arrayContains: user.uid)
        .snapshots()
        .listen((convSnapshot) {
          _rebuildNotifications(convSnapshot.docs);
        });
  }

  Future<void> _rebuildNotifications(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> convDocs,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final notifications = <NotificationItem>[];
    final sellerIds = <String>{};

    for (var doc in convDocs) {
      final data = doc.data();
      final participants = List<String>.from(data['participants'] ?? []);
      final otherId = participants.firstWhere(
        (id) => id != user.uid,
        orElse: () => '',
      );
      if (otherId.isNotEmpty) sellerIds.add(otherId);

      final unread = data['unreadCount'] ?? 0;
      if (unread > 0) {
        final lastMsg = data['lastMessage'] ?? '';
        final otherName = data['otherUserName'] ?? 'Unknown';
        final lastTime = data['lastMessageTime'] is Timestamp
            ? (data['lastMessageTime'] as Timestamp).toDate()
            : DateTime.now();

        notifications.add(
          NotificationItem(
            id: 'chat_${doc.id}',
            type: 'chat',
            title: otherName,
            body: lastMsg,
            timestamp: lastTime,
            otherUserId: otherId,
            otherUserName: otherName,
            otherUserImage: data['otherUserImage'] as String?,
            isRead: false,
            unreadCount: unread,
          ),
        );
      }
    }

    if (sellerIds.isNotEmpty) {
      try {
        final productsSnapshot = await FirebaseFirestore.instance
            .collection("products")
            .where("isActive", isEqualTo: true)
            .orderBy("createdAt", descending: true)
            .limit(50)
            .get();

        for (var doc in productsSnapshot.docs) {
          final data = doc.data();
          final sellerId = data['sellerId'] as String? ?? '';
          if (!sellerIds.contains(sellerId)) continue;

          final created = data['createdAt'] is Timestamp
              ? (data['createdAt'] as Timestamp).toDate()
              : DateTime.now();
          final images = List<String>.from(data['images'] ?? []);

          notifications.add(
            NotificationItem(
              id: 'product_${doc.id}',
              type: 'product',
              title: data['sellerName'] ?? 'Seller',
              body: data['name'] ?? '',
              timestamp: created,
              otherUserId: sellerId,
              otherUserName: data['sellerName'] as String?,
              productId: doc.id,
              productImage: images.isNotEmpty ? images.first : null,
            ),
          );
        }
      } catch (_) {}
    }

    notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (mounted) {
      _notifications = notifications;
      _loading = false;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('notifications'))),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _notifications.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.notifications_none,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      context.tr('no_notifications'),
                      style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                    ),
                  ],
                ),
              )
            : ListView.separated(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom + 20,
                ),
                itemCount: _notifications.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final notif = _notifications[index];
                  return _buildNotificationTile(notif);
                },
              ),
      ),
    );
  }

  Widget _buildNotificationTile(NotificationItem notif) {
    final isChat = notif.type == 'chat';

    IconData icon;
    Color iconColor;
    if (isChat) {
      icon = Icons.message;
      iconColor = Colors.blue;
    } else {
      icon = Icons.shopping_bag;
      iconColor = Colors.orange;
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: iconColor.withValues(alpha: 0.1),
        child: Icon(icon, color: iconColor, size: 22),
      ),
      title: Text(
        notif.title,
        style: TextStyle(
          fontWeight: notif.unreadCount > 0
              ? FontWeight.bold
              : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        notif.body,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Colors.grey[600], fontSize: 13),
      ),
      trailing: notif.unreadCount > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${notif.unreadCount}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            )
          : null,
      onTap: () => _openNotification(notif),
    );
  }

  void _openNotification(NotificationItem notif) {
    if (notif.type == 'chat' && notif.otherUserId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatPage(
            receiverId: notif.otherUserId!,
            receiverName: notif.otherUserName ?? '',
          ),
        ),
      );
    } else if (notif.type == 'product' && notif.productId != null) {
      ProductService().getProductById(notif.productId!).then((product) {
        if (product != null && mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProductDetailPage(product: product),
            ),
          );
        }
      });
    }
  }
}
