import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../services/notification_service.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';
import '../../widgets/google_loading.dart';
import '../../widgets/ad_banner.dart';

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

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return _buildErrorScaffold();
        if (!snap.hasData) return _buildLoadingScaffold();

        final docs = snap.data!.docs;
        final unreadCount = docs.where((d) => !(d['isRead'] as bool)).length;

        return Scaffold(
          appBar: AppBar(
            title: Text(context.tr('notifications')),
            actions: [
              if (unreadCount > 0)
                TextButton(
                  onPressed: () => _markAllRead(),
                  child: Text('${context.tr('mark_all_read')} ($unreadCount)'),
                ),
            ],
          ),
          body: docs.isEmpty
              ? _emptyState(context)
              : _buildNotificationList(docs),
          bottomNavigationBar: const AdBanner(),
        );
      },
    );
  }

  Widget _emptyState(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notifications_none, size: 64,
              color: cs.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            context.tr('no_notifications'),
            style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Future<void> _markAllRead() async {
    await _notifService.markAllAsRead();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('mark_all_read'))),
      );
    }
  }

  Widget _buildNotificationList(List<QueryDocumentSnapshot> docs) {
    return ListView.separated(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 20,
      ),
      itemCount: docs.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final doc = docs[index];
        final data = doc.data() as Map<String, dynamic>;
        return Dismissible(
          key: ValueKey(doc.id),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Theme.of(context).colorScheme.error,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child: Icon(Icons.delete_outline,
                color: Theme.of(context).colorScheme.surface),
          ),
          confirmDismiss: (_) async {
            final deleted = await _notifService.deleteNotification(doc.id);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(deleted
                      ? context.tr('notification_deleted')
                      : context.tr('something_wrong')),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
            return deleted;
          },
          child: _buildTile(doc.id, data),
        );
      },
    );
  }

  Scaffold _buildLoadingScaffold() {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('notifications'))),
      body: const GoogleLoadingPage(),
      bottomNavigationBar: const AdBanner(),
    );
  }

  Scaffold _buildErrorScaffold() {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('notifications'))),
      body: _emptyState(context),
      bottomNavigationBar: const AdBanner(),
    );
  }

  Widget _buildTile(String docId, Map<String, dynamic> data) {
    final cs = Theme.of(context).colorScheme;
    final title = data['title'] as String? ?? '';
    final body = data['body'] as String? ?? '';
    final isRead = data['isRead'] as bool? ?? false;
    final rawData = data['data'] is Map ? data['data'] as Map : null;
    final type = rawData?['type'] as String? ?? data['type'] as String? ?? '';

    IconData icon;
    Color color;
    switch (type) {
      case 'chat':
        icon = Icons.chat; color = Colors.blue;
      case 'group_chat':
        icon = Icons.group; color = Colors.teal;
      case 'order':
        icon = Icons.shopping_bag; color = Colors.green;
      case 'boost':
        icon = Icons.rocket_launch; color = Colors.orange;
      case 'flash_sale':
        icon = Icons.flash_on; color = Colors.amber;
      case 'escrow_release':
      case 'escrow_auto_release':
        icon = Icons.account_balance_wallet; color = Colors.indigo;
      case 'dispatched':
        icon = Icons.local_shipping; color = Colors.orange;
      case 'disputed':
        icon = Icons.gavel; color = Colors.red;
      case 'failed_retry':
        icon = Icons.warning_amber; color = Colors.deepOrange;
      case 'dispute_resolved':
        icon = Icons.balance; color = Colors.teal;
      case 'delivery_confirmed':
        icon = Icons.check_circle; color = Colors.green;
      case 'price_drop':
        icon = Icons.trending_down; color = Colors.red;
      case 'bulk':
        icon = Icons.campaign; color = Colors.purple;
      default:
        icon = Icons.notifications; color = cs.tertiary;
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.1),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(
        title,
        style: TextStyle(fontWeight: isRead ? FontWeight.normal : FontWeight.bold),
      ),
      subtitle: Text(
        body,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
      ),
      trailing: isRead
          ? null
          : Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: cs.primary,
                shape: BoxShape.circle,
              ),
            ),
      onTap: () {
        if (!isRead) _notifService.markAsRead(docId);
        final senderId = rawData?['senderId'] as String?;
        final groupId = rawData?['groupId'] as String?;
        switch (type) {
          case 'chat':
            if (senderId != null) {
              context.push('/chat/$senderId', extra: {'name': rawData?['senderName'] ?? ''});
            } else {
              context.push(AppRoutes.chats);
            }
            break;
          case 'group_chat':
            if (groupId != null) {
              context.push('/group-chat/$groupId');
            } else {
              context.push(AppRoutes.chats);
            }
            break;
          case 'order':
          case 'escrow_release':
          case 'escrow_auto_release':
          case 'delivery_confirmed':
          case 'dispatched':
          case 'disputed':
          case 'dispute_resolved':
          case 'failed_retry':
            context.push(AppRoutes.myPurchases);
            break;
          case 'boost':
            context.push(AppRoutes.notifications);
            break;
          case 'flash_sale':
            context.push(AppRoutes.flashSale);
            break;
          case 'price_drop':
            context.push(AppRoutes.notifications);
            break;
          case 'product':
            context.push(AppRoutes.notifications);
            break;
          default:
            context.push(AppRoutes.notifications);
        }
      },
    );
  }
}
