import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../services/notification_service.dart';
import '../../services/notification_lang.dart';
import '../../services/notification_api.dart';
import '../../services/api_config.dart';
import '../../models/notification_item.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';
import '../../main.dart' show AppConfig;
import '../../widgets/ds/ds.dart';
import '../../widgets/soko_vibe_states.dart';
import '../../widgets/soko_widgets.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final NotificationService _notifService = NotificationService();
  final NotificationApiClient _api = NotificationApiClient();
  DateTime? _lastTileTapAt;

  // Created ONCE and reused.
  //
  // Both of these were previously constructed inline in build(): the v1 future
  // re-issued an HTTP request on every rebuild, and the Firestore stream
  // re-subscribed (and re-billed a full read) on every rebuild. Because each
  // completion triggers setState → rebuild, both were self-sustaining loops that
  // ran until the user navigated away — `_buildV1Body` alone was two HTTP calls
  // per iteration, because fetchUnreadCount is nested inside fetchNotifications.
  late final Future<({List<NotificationItem> notifications, int unreadCount})>
      _v1Future;
  StreamSubscription<QuerySnapshot>? _fsSub;
  QuerySnapshot? _fsSnapshot;
  Object? _fsError;
  bool _fsLoading = true;

  @override
  void initState() {
    super.initState();
    _v1Future = _api.fetchNotifications();
    _subscribeFirestore();
  }

  /// The Firestore fallback path (used when `kUseNotificationsApi` is false).
  ///
  /// Subscribed once and torn down in [dispose] rather than being handed a new
  /// stream to `StreamBuilder` on each build.
  void _subscribeFirestore() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _fsLoading = false;
      return;
    }
    _fsSub = FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        // Bounded: an unbounded user-scoped listener re-bills its whole result
        // set every time any document in it changes.
        .limit(60)
        .snapshots()
        .listen(
      (snap) {
        if (!mounted) return;
        setState(() {
          _fsSnapshot = snap;
          _fsLoading = false;
          _fsError = null;
        });
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _fsError = e;
          _fsLoading = false;
        });
      },
    );
  }

  @override
  void dispose() {
    _fsSub?.cancel();
    _fsSub = null;
    super.dispose();
  }

  /// Forces a refetch after a mutation (mark-all-read, delete-all).
  void _reload() {
    setState(() => _v1Future = _api.fetchNotifications());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(title: Text(context.tr('notifications'))),
        body: Center(child: Text(context.tr('login_required'))),
      );
    }

    if (ApiConfig.kUseNotificationsApi) {
      return _buildV1Body(cs);
    }

    if (_fsLoading) return _buildLoadingScaffold(cs);
    if (_fsError != null) return _buildErrorScaffold(cs);
    return _buildFirestoreBody(cs, _fsSnapshot);
  }

  /// Firestore-backed list, rendered from the snapshot held in state.
  Widget _buildFirestoreBody(ColorScheme cs, QuerySnapshot? snap) {
    final docs = snap?.docs ?? const <QueryDocumentSnapshot>[];
    // Snapshot `[]` throws for fields absent from a doc; legacy rows predate
    // isRead, so read through the Map which defaults to null.
    final unreadCount = docs
        .where((d) => ((d.data() as Map)['isRead'] as bool?) != true)
        .length;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(context.tr('notifications')),
        actions: [
          IconButton(
            tooltip: context.tr('notification_settings'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push(AppRoutes.notificationPreferences),
          ),
          if (unreadCount > 0)
            TextButton(
              onPressed: () => _markAllRead(),
              child: Text('${context.tr('mark_all_read')} ($unreadCount)'),
            ),
          if (docs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: context.tr('clear_all'),
              onPressed: () => _deleteAll(docs),
            ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [cs.surface, cs.surfaceContainerLow.withValues(alpha: 0.3)],
          ),
        ),
        child: docs.isEmpty
            ? _emptyState(context)
            : _buildNotificationList(cs, docs),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return SokoVibeEmptyState(
      icon: Icons.notifications_none,
      title: context.tr('no_notifications'),
    );
  }

  Future<void> _markAllRead() async {
    if (ApiConfig.kUseNotificationsApi) {
      await _api.markAllRead();
    } else {
      await _notifService.markAllAsRead();
    }
    if (mounted) {
      SokoSnackbar.info(context, context.tr('mark_all_read'));
    }
    // Refresh the ONE future this screen reads. The bare `setState(() {})`
    // used to be relied on to re-trigger the FutureBuilder — which only worked
    // because the future was rebuilt in build(), i.e. by re-requesting on every
    // rebuild. Now the refresh is explicit.
    if (ApiConfig.kUseNotificationsApi) _reload();
  }

  /// Batch-deletes every notification and shows how many were removed so the
  /// user has feedback when swiping-heavy cleanup leaves the list empty.
  Future<void> _deleteAll(List<QueryDocumentSnapshot> docs) async {
    final confirmed = await SokoDialog.show(
      context,
      variant: SokoDialogVariant.danger,
      icon: Icons.delete_outline_rounded,
      title: context.tr('clear_all'),
      message:
          '${context.tr('confirm_clear_notifications', 'Delete all notifications?')} '
          '(${docs.length})',
      confirmLabel: context.tr('clear_all'),
      cancelLabel: context.tr('cancel', 'Cancel'),
    );
    if (confirmed != true || !mounted) return;

    var deleted = 0;
    for (final doc in docs) {
      if (await _notifService.deleteNotification(doc.id)) deleted++;
    }
    if (!mounted) return;
    SokoSnackbar.show(
      context,
      message: context.tr(
        'deleted_notifications_count',
        '$deleted ${context.tr('notifications_deleted', 'notifications deleted')}',
      ),
      duration: const Duration(seconds: 2),
    );
  }

  /// v1-backed batch delete: the server deletes the whole inbox in one call
  /// (no count needed, so a generic confirmation + short success message).
  Future<void> _deleteAllV1() async {
    final confirmed = await SokoDialog.show(
      context,
      variant: SokoDialogVariant.danger,
      icon: Icons.delete_outline_rounded,
      title: context.tr('clear_all'),
      message: context.tr('confirm_clear_notifications', 'Delete all notifications?'),
      confirmLabel: context.tr('clear_all'),
      cancelLabel: context.tr('cancel', 'Cancel'),
    );
    if (confirmed != true || !mounted) return;

    final deleted = await _api.deleteAll();
    if (!mounted) return;
    _reload();
    SokoSnackbar.show(
      context,
      message: context.tr(
        'deleted_notifications_count',
        '$deleted ${context.tr('notifications_deleted', 'notifications deleted')}',
      ),
      duration: const Duration(seconds: 2),
    );
  }

  /// Opens the destination for a tapped notification. A fast second tap on the
  /// same tile races the first route transition and leaves duplicate page
  /// entries whose teardown triggers the framework's element bookkeeping assert
  /// (_InactiveElements), so re-entrant pushes are ignored for a short window.
  void _openFromTile(BuildContext context, String type, Map? rawData) {
    final tappedAt = DateTime.now();
    if (_lastTileTapAt != null &&
        tappedAt.difference(_lastTileTapAt!).inMilliseconds < 400) {
      return;
    }
    _lastTileTapAt = tappedAt;

    final senderId = rawData?['senderId'] as String?;
    final groupId = rawData?['groupId'] as String?;
    final myUid = FirebaseAuth.instance.currentUser?.uid;
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
      case 'sale':
      case 'payment':
      case 'escrow_confirm':
      case 'escrow_release':
      case 'escrow_auto_release':
      case 'delivery_confirmed':
      case 'dispatched':
      case 'buyer_transport':
      case 'shipping_quote':
      case 'disputed':
      case 'dispute_resolved':
      case 'failed_retry': {
        final orderId =
            (rawData?['orderId'] ?? rawData?['transactionId']) as String?;
        if (orderId != null && orderId.isNotEmpty) {
          // Order notifications carry the OTHER party's id: to-buyer
          // notifications include sellerId, to-seller ones include buyerId.
          // A seller who got "set the shipping cost for this new order"
          // (the only to-seller order notice carrying productId) lands on
          // the quote screen; other seller notices act on order detail.
          final isNewOrderForSeller = myUid != null &&
              rawData?['sellerId'] == null &&
              rawData?['buyerId'] != null &&
              rawData?['productId'] != null;
          if (isNewOrderForSeller) {
            context.push(AppRoutes.sellerQuote);
          } else {
            context.push('${AppRoutes.orderDetail}/$orderId');
          }
        } else {
          // myPurchases lists only the buyer's transactions; a seller
          // notification must land on the seller's orders screen instead.
          // Order notifications carry the other party's id: to-buyer
          // notifications include sellerId, to-seller ones include buyerId.
          final isBuyerRecipient = myUid != null && rawData?['sellerId'] != null;
          context.push(isBuyerRecipient ? AppRoutes.myPurchases : AppRoutes.sellerOrders);
        }
        break;
      }
      case 'comment':
      case 'comment_reply': {
        final pid = rawData?['productId'] as String?;
        if (pid != null) {
          context.push('/product/$pid');
        }
        break;
      }
      case 'flash_sale':
        context.push(AppRoutes.flashSale);
        break;
      case 'product':
        break;
      default:
        break;
    }
  }

  Widget _buildNotificationList(ColorScheme cs, List<QueryDocumentSnapshot> docs) {
    return ListView.separated(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 20),
      itemCount: docs.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final doc = docs[index];
        final data = doc.data() as Map<String, dynamic>;
        return Dismissible(
          key: ValueKey(doc.id),
          direction: DismissDirection.endToStart,
          background: Container(
            color: cs.error,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child: Icon(Icons.delete_outline, color: cs.surface),
          ),
          confirmDismiss: (_) async {
            final deleted = await _notifService.deleteNotification(doc.id);
            if (mounted) {
              SokoSnackbar.show(
                context,
                message: deleted
                    ? context.tr('notification_deleted')
                    : context.tr('something_wrong'),
                type: deleted ? SokoSnackType.success : SokoSnackType.error,
              );
            }
            return deleted;
          },
          child: _buildTile(cs, doc.id, data),
        );
      },
    );
  }

  Widget _buildV1NotificationList(ColorScheme cs, List<NotificationItem> items) {
    return ListView.separated(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 20),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        return Dismissible(
          key: ValueKey(item.id),
          direction: DismissDirection.endToStart,
          background: Container(
            color: cs.error,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child: Icon(Icons.delete_outline, color: cs.surface),
          ),
          confirmDismiss: (_) async {
            final deleted = await _api.delete(item.id);
            if (mounted) {
              SokoSnackbar.show(
                context,
                message: deleted
                    ? context.tr('notification_deleted')
                    : context.tr('something_wrong'),
                type: deleted ? SokoSnackType.success : SokoSnackType.error,
              );
            }
            return deleted;
          },
          child: _buildV1Tile(cs, item),
        );
      },
    );
  }

  Widget _buildV1Tile(ColorScheme cs, NotificationItem item) {
    var title = item.title;
    var body = item.body;
    if (item.type != 'chat' && item.type != 'group_chat') {
      final localized = NotificationLang.localize(
        AppConfig.maybeOf(context)?.langCode ?? 'sw',
        title,
        body,
      );
      title = localized.title;
      body = localized.body;
    }

    final rawData = {'type': item.type, 'senderId': item.otherUserId, 'senderName': item.otherUserName, 'senderAvatar': item.otherUserImage, 'productId': item.productId, 'image': item.productImage};

    return NotificationCard(
      item: item,
      onTap: () {
        if (!item.isRead) _api.markRead(item.id);
        _openFromTile(context, item.type, rawData);
      },
    );
  }

  Scaffold _buildLoadingScaffold(ColorScheme cs) {
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(title: Text(context.tr('notifications'))),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [cs.surface, cs.surfaceContainerLow.withValues(alpha: 0.3)],
          ),
        ),
        child: ListView.separated(
          padding: EdgeInsets.only(top: 16, bottom: MediaQuery.of(context).padding.bottom + 20),
          itemCount: 8,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, _) => const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                DsSkeleton(shape: DsSkeletonShape.circle, width: 40, height: 40),
                SizedBox(width: 14),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DsSkeleton(width: 180, height: 12),
                    SizedBox(height: 8),
                    DsSkeleton(width: double.infinity, height: 10),
                  ],
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// v1-backed notification list (Postgres /api/v1/notifications). The server
  /// envelope maps into the same tile model as the Firestore docs, so the
  /// remaining UI (card render, tap routing, swipe delete) is shared.
  Widget _buildV1Body(ColorScheme cs) {
    return FutureBuilder<({List<NotificationItem> notifications, int unreadCount})>(
      // `late final` created in initState, NOT a fresh call here. Constructing
      // the future inside build() meant every rebuild issued a new request, and
      // every completion called setState, which rebuilt — an unbounded loop.
      future: _v1Future,
      builder: (context, snap) {
        if (snap.hasError) return _buildErrorScaffold(cs);
        if (!snap.hasData) return _buildLoadingScaffold(cs);

        final items = snap.data!.notifications;
        final unreadCount = snap.data!.unreadCount;

        return Scaffold(
          backgroundColor: cs.surface,
          appBar: AppBar(
            title: Text(context.tr('notifications')),
            actions: [
              IconButton(
                tooltip: context.tr('notification_settings'),
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => context.push(AppRoutes.notificationPreferences),
              ),
              if (unreadCount > 0)
                TextButton(
                  onPressed: () => _markAllRead(),
                  child: Text('${context.tr('mark_all_read')} ($unreadCount)'),
                ),
              if (items.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined),
                  tooltip: context.tr('clear_all'),
                  onPressed: () => _deleteAllV1(),
                ),
            ],
          ),
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [cs.surface, cs.surfaceContainerLow.withValues(alpha: 0.3)],
              ),
            ),
            child: items.isEmpty
                ? _emptyState(context)
                : _buildV1NotificationList(cs, items),
          ),
        );
      },
    );
  }

  Scaffold _buildErrorScaffold(ColorScheme cs) {
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(title: Text(context.tr('notifications'))),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [cs.surface, cs.surfaceContainerLow.withValues(alpha: 0.3)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 64, color: cs.error),
              const SizedBox(height: 16),
              Text(context.tr('trouble_connecting'), style: const TextStyle(fontSize: 16), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => setState(() {}),
                icon: const Icon(Icons.refresh),
                label: Text(context.tr('try_again')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTile(ColorScheme cs, String docId, Map<String, dynamic> data) {
    var title = data['title'] as String? ?? '';
    var body = data['body'] as String? ?? '';
    final isRead = data['isRead'] as bool? ?? false;
    final rawData = data['data'] is Map ? data['data'] as Map : null;
    final type = rawData?['type'] as String? ?? data['type'] as String? ?? '';

    // Server stores notification copies as Swahili; localize them here to the
    // user's in-app language. Chat messages are user-generated text, not
    // templates, so keep them verbatim.
    if (type != 'chat' && type != 'group_chat') {
      final localized = NotificationLang.localize(
        AppConfig.maybeOf(context)?.langCode ?? 'sw',
        title,
        body,
      );
      title = localized.title;
      body = localized.body;
    }

    final rawTimestamp = data['timestamp'];
    final timestamp = switch (rawTimestamp) {
      Timestamp t => t.toDate(),
      DateTime dt => dt,
      _ => DateTime.now(),
    };

    final item = NotificationItem(
      id: docId,
      type: type,
      title: title,
      body: body,
      timestamp: timestamp,
      otherUserId: rawData?['senderId'] as String?,
      otherUserName: rawData?['senderName'] as String?,
      otherUserImage: rawData?['senderAvatar'] as String?,
      productId: rawData?['productId'] as String?,
      productImage: (data['image'] as String?) ?? (rawData?['image'] as String?),
      isRead: isRead,
    );

    return NotificationCard(
      item: item,
      onTap: () {
        if (!isRead) _notifService.markAsRead(docId);
        _openFromTile(context, type, rawData);
      },
    );
  }
}
