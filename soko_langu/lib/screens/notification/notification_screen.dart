import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../services/notification_service.dart';
import '../../services/product_service.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';
import '../../widgets/google_loading.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final NotificationService _notifService = NotificationService();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('notifications'))),
        body: Center(child: Text(context.tr('login_required'))),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('notifications')),
        actions: [
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('notifications')
                .where('userId', isEqualTo: user.uid)
                .where('isRead', isEqualTo: false)
                .snapshots(),
            builder: (context, snap) {
              final unread = snap.data?.docs.length ?? 0;
              if (unread == 0) return const SizedBox.shrink();
              return TextButton(
                onPressed: () => _notifService.markAllAsRead(),
                child: Text('${context.tr('mark_all_read')} ($unread)'),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('notifications')
            .where('userId', isEqualTo: user.uid)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.notifications_none, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    context.tr('no_notifications'),
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }
          if (!snap.hasData) return const GoogleLoadingPage();

          final docs = snap.data!.docs;
          docs.sort((a, b) {
            final ta = (a.data() as Map)['createdAt'];
            final tb = (b.data() as Map)['createdAt'];
            if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
            return 0;
          });
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.notifications_none, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    context.tr('no_notifications'),
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).padding.bottom + 20,
            ),
            itemCount: docs.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              return _buildTile(doc.id, data);
            },
          );
        },
      ),
    );
  }

  Widget _buildTile(String docId, Map<String, dynamic> data) {
    final title = data['title'] as String? ?? '';
    final body = data['body'] as String? ?? '';
    final isRead = data['isRead'] as bool? ?? false;
    final type = data['data'] is Map ? (data['data'] as Map)['type'] as String? : data['type'] as String?;
    final notifType = type ?? 'general';

    IconData icon;
    Color iconColor;
    switch (notifType) {
      case 'chat':
        icon = Icons.message;
        iconColor = Colors.blue;
        break;
      case 'flash_sale':
        icon = Icons.flash_on;
        iconColor = Colors.orange;
        break;
      case 'order':
        icon = Icons.shopping_bag;
        iconColor = Colors.green;
        break;
      case 'product':
        icon = Icons.sell;
        iconColor = Colors.purple;
        break;
      case 'system':
        icon = Icons.info_outline;
        iconColor = Colors.grey;
        break;
      default:
        icon = Icons.notifications_outlined;
        iconColor = Colors.teal;
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: iconColor.withValues(alpha: 0.1),
        child: Icon(icon, color: iconColor, size: 22),
      ),
      title: Text(
        title,
        style: TextStyle(fontWeight: isRead ? FontWeight.normal : FontWeight.bold),
      ),
      subtitle: Text(
        body,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Colors.grey[600], fontSize: 13),
      ),
      trailing: isRead
          ? null
          : Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
              ),
            ),
      onTap: () {
        if (!isRead) _notifService.markAsRead(docId);
        _openNotification(notifType, data);
      },
    );
  }

  void _openNotification(String type, Map<String, dynamic> data) {
    final notifData = data['data'] is Map ? data['data'] as Map<String, dynamic> : null;

    if (type == 'chat') {
      final otherId = notifData?['senderId'] as String? ?? '';
      final otherName = notifData?['senderName'] as String? ?? '';
      if (otherId.isNotEmpty) {
        context.push('${AppRoutes.chat}/$otherId', extra: {'name': otherName});
      }
    } else if (type == 'flash_sale') {
      context.push(AppRoutes.flashSale);
    } else if (type == 'product') {
      final productId = notifData?['productId'] as String? ?? '';
      if (productId.isNotEmpty) {
        ProductService().getProductById(productId).then((product) {
          if (product != null && mounted) {
            context.push('${AppRoutes.productDetail}/${product.id}', extra: product);
          }
        });
      }
    }
  }
}
