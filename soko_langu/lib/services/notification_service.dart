import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'api_config.dart';
import 'local_notification_service.dart';

class NotificationService {
  static const String _key = 'push_notifications_enabled';

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _initialized = false;
  bool _listenersRegistered = false;
  bool _pushDenied = false;
  StreamSubscription<QuerySnapshot>? _fallbackSub;
  final Set<String> _seenFallbackIds = {};

  final StreamController<int> _unreadController = StreamController<int>.broadcast();
  Stream<int> get unreadCountStream => _unreadController.stream;

  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  static void Function(Map<String, dynamic> data)? onNotificationTap;
  static void Function(Map<String, dynamic> data)? onPaymentNotificationTap;

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? true;
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
    if (value) {
      _initialized = false;
      await initialize();
    } else {
      OneSignal.Notifications.clearAll();
      await OneSignal.logout();
      _fallbackSub?.cancel();
      _fallbackSub = null;
      _seenFallbackIds.clear();
      _pushDenied = false;
      _initialized = false;
    }
  }

  Future<void> initialize() async {
    try {
      if (!await isEnabled()) {
        debugPrint('[OS] notifications disabled by user preference');
        return;
      }

      if (_initialized) return;

      // Initialize local notifications first for heads-up display
      await LocalNotificationService().initialize();
      LocalNotificationService.onTap = _handleLocalTap;

      OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
      OneSignal.initialize(ApiConfig.oneSignalAppId);

      final perm = await OneSignal.Notifications.requestPermission(true);
      debugPrint('[OS] permission result: $perm');
      _pushDenied = !perm;
      if (_pushDenied) {
        // Push denied — mirror in-app notifications as heads-up via Firestore
        // so critical events are still visible without push permission.
        _startFirestoreFallback();
      } else {
        _fallbackSub?.cancel();
        _fallbackSub = null;
      }

      final user = _auth.currentUser;
      if (user != null) {
        OneSignal.login(user.uid);
        debugPrint('[OS] logged in user ${user.uid}');
        if (user.email != null && user.email!.isNotEmpty) {
          OneSignal.User.addEmail(user.email!);
          debugPrint('[OS] registered email: ${user.email}');
        }
      }

      if (!_listenersRegistered) {
        // Handle notification tap (app opened from notification)
        OneSignal.Notifications.addClickListener((event) {
          final data = event.notification.additionalData ?? {};
          debugPrint('[OS] notification tapped: type=${data['type']}');
          _onNotificationTapped(data);
        });

        // Handle notification received while app is in foreground — show heads-up
        OneSignal.Notifications.addForegroundWillDisplayListener((event) {
          event.preventDefault();
          final notif = event.notification;
          final data = notif.additionalData ?? {};
          final title = notif.title ?? '';
          final body = notif.body ?? '';
          final type = data['type'] as String? ?? 'general';
          debugPrint('[OS] foreground notification: type=$type title=$title');
          _showHeadsUpNotification(title, body, type, data);
        });

        // Re-login when auth state changes
        _auth.authStateChanges().listen((user) async {
          if (user != null) {
            OneSignal.login(user.uid);
            debugPrint('[OS] auth change — logged in ${user.uid}');
            if (user.email != null && user.email!.isNotEmpty) {
              OneSignal.User.addEmail(user.email!);
            }
            if (_pushDenied) _startFirestoreFallback();
          } else {
            await OneSignal.logout();
            _fallbackSub?.cancel();
            _fallbackSub = null;
            _seenFallbackIds.clear();
            debugPrint('[OS] auth change — logged out');
          }
        });

        debugPrint('[OS] handlers registered');
        // Set AFTER all handlers are attached so a mid-registration exception
        // leaves retries possible (otherwise _listenersRegistered stays true).
        _listenersRegistered = true;
      }

      _initialized = true;
      debugPrint('[OS] initialized');
      _syncBadge();
    } catch (e) {
      _initialized = false;
      debugPrint('[OS] Notification init error: $e');
    }
  }

  void _showHeadsUpNotification(String title, String body, String type, Map<String, dynamic> data) {
    final String channelId;
    final String headsUpTitle;
    final List<AndroidNotificationAction> actions = [];

    switch (type) {
      case 'chat':
      case 'group_chat':
        channelId = 'chat_messages_v6';
        headsUpTitle = data['senderName'] as String? ?? title;
        actions.add(const AndroidNotificationAction('reply', 'Jibu', showsUserInterface: true));
        break;
      case 'payment':
      case 'payment_failed':
      case 'refund':
      case 'cancelled':
      case 'withdrawal':
      case 'escrow_auto_release':
      case 'auto_payout':
      case 'order':
      case 'dispatched':
      case 'delivery_confirmed':
      case 'kyc':
      case 'kyc_approved':
      case 'kyc_rejected':
      case 'kyc_revoked':
      case 'deposit':
      case 'deposit_failed':
        channelId = 'payments_notifications_v6';
        headsUpTitle = title;
        final hasOrder = data['orderId'] != null || data['transactionId'] != null;
        // sellerId marks the shipping-quote push to the buyer — pay button
        if (type == 'payment' || (type == 'order' && data['sellerId'] != null)) {
          if (hasOrder) {
            actions.add(const AndroidNotificationAction('pay', 'Lipa Sasa', showsUserInterface: true));
          }
        }
        if (type == 'dispatched' || type == 'delivery_confirmed') {
          if (hasOrder) {
            actions.add(const AndroidNotificationAction('confirm', 'Thibitisha Upokeaji', showsUserInterface: true));
          }
        }
        break;
      case 'boost':
      case 'promotion':
        channelId = 'general_notifications_v6';
        headsUpTitle = title;
        break;
      case 'flash_sale':
      case 'new_product':
        channelId = 'general_notifications_v6';
        headsUpTitle = title;
        break;
      case 'system':
      case 'admin':
      case 'alert':
        channelId = 'system_alerts_v6';
        headsUpTitle = title;
        break;
      default:
        channelId = 'general_notifications_v6';
        headsUpTitle = title;
    }

    // payload carries type + data so a local tap routes like a OneSignal tap
    final payload = jsonEncode({'type': type, ...data});

    final id = LocalNotificationService.nextNotificationId();
    debugPrint('[OS] local heads-up → id=$id channel=$channelId title=$headsUpTitle');
    LocalNotificationService().showHeadsUp(
      id: id,
      title: headsUpTitle,
      body: body,
      channelId: channelId,
      payload: payload,
      actions: actions,
    );
  }

  static void _handleLocalTap(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    final action = data['action'] as String?;
    debugPrint('[OS] local notification tapped: type=$type action=$action');
    if ((type == 'payment' || action == 'pay') && onPaymentNotificationTap != null) {
      onPaymentNotificationTap!(data);
    } else if (onNotificationTap != null) {
      onNotificationTap!(data);
    }
  }

  static void _onNotificationTapped(Map<String, dynamic> data) {
    debugPrint('[OS] _onNotificationTapped: type=${data['type']}');
    if (data['type'] == 'payment' && onPaymentNotificationTap != null) {
      onPaymentNotificationTap!(data);
    } else if (onNotificationTap != null) {
      onNotificationTap!(data);
    }
  }

  Future<void> sendNotification({
    required String userId,
    required String title,
    String body = '',
    Map<String, String> data = const {},
  }) async {
    try {
      debugPrint('[OS] sendNotification to $userId: $title');
      final token = await _auth.currentUser?.getIdToken();
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/send-notification'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'userId': userId,
          'title': title,
          'body': body,
          'data': data,
        }),
      );
      debugPrint('[OS] sendNotification response: ${response.statusCode}');
    } catch (e) {
      debugPrint('[OS] sendNotification error: $e');
    }
  }

  Future<void> registerEmail(String email) async {
    try {
      OneSignal.User.addEmail(email);
      debugPrint('[OS] registered email: $email');
    } catch (e) {
      debugPrint('[OS] registerEmail error: $e');
    }
  }

  Future<void> unregisterEmail(String email) async {
    try {
      OneSignal.User.removeEmail(email);
      debugPrint('[OS] unregistered email: $email');
    } catch (e) {
      debugPrint('[OS] unregisterEmail error: $e');
    }
  }

  Stream<List<Map<String, dynamic>>> getNotifications() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);
    return _db
        .collection('notifications')
        .where('userId', isEqualTo: user.uid)
        .snapshots()
        .map(
          (snap) {
            final list = snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList()
              ..sort((a, b) {
                final ta = a['createdAt'];
                final tb = b['createdAt'];
                if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
                return 0;
              });
            final unread = list.where((n) => n['isRead'] != true).length;
            _unreadController.add(unread);
            return list;
          },
        );
  }

  Future<void> _syncBadge() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      final snap = await _db
          .collection('notifications')
          .where('userId', isEqualTo: user.uid)
          .where('isRead', isEqualTo: false)
          .count()
          .get();
      final count = snap.count ?? 0;
      _unreadController.add(count);
    } catch (_) {
      // non-critical
    }
  }

  Future<void> markAsRead(String notifId) async {
    try {
      await _db.collection('notifications').doc(notifId).update({'isRead': true});
    } catch (e) {
      debugPrint('markAsRead: $e');
    }
  }

  Future<void> markAllAsRead() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      DocumentSnapshot? lastDoc;
      while (true) {
        var query = _db
            .collection('notifications')
            .where('userId', isEqualTo: user.uid)
            .where('isRead', isEqualTo: false)
            .limit(500);
        if (lastDoc != null) query = query.startAfterDocument(lastDoc);
        final snap = await query.get();
        if (snap.docs.isEmpty) break;
        final batch = _db.batch();
        for (var doc in snap.docs) {
          batch.update(doc.reference, {'isRead': true});
        }
        await batch.commit();
        lastDoc = snap.docs.last;
      }
    } catch (e) {
      debugPrint('markAllAsRead: $e');
    }
  }

  /// Marks unread in-app notifications matching this tap as read so the badge
  /// clears even when the user opened the app via a push instead of the list.
  Future<void> markRelatedAsRead(String? type, Map<String, dynamic>? data) async {
    final user = _auth.currentUser;
    if (user == null || type == null || type.isEmpty) return;
    try {
      final snap = await _db
          .collection('notifications')
          .where('userId', isEqualTo: user.uid)
          .limit(500)
          .get();
      final candidates = snap.docs.where((doc) {
        final d = doc.data();
        return d['isRead'] != true && d['type'] == type;
      }).toList();
      if (candidates.isEmpty) return;

      final idKeys = ['orderId', 'transactionId', 'productId', 'roomId', 'payoutId', 'depositRef'];
      final expected = <String, String>{};
      for (final key in idKeys) {
        final value = data?[key];
        if (value != null) expected[key] = value.toString();
      }

      final batch = _db.batch();
      for (final doc in candidates) {
        final docData = doc.data();
        final matches = expected.entries.every((entry) {
          final dataMap = docData['data'];
          if (dataMap is! Map) return false;
          return dataMap[entry.key]?.toString() == entry.value;
        });
        if (expected.isEmpty || matches) {
          batch.update(doc.reference, {'isRead': true});
        }
      }
      await batch.commit();
      _syncBadge();
    } catch (e) {
      debugPrint('markRelatedAsRead: $e');
    }
  }

  /// Firestore fallback for users who denied push — new in-app rows become
  /// heads-up notifications so critical events are never missed.
  void _startFirestoreFallback() {
    final user = _auth.currentUser;
    if (user == null || _fallbackSub != null) return;
    _seenFallbackIds.clear();
    _fallbackSub = _db
        .collection('notifications')
        .where('userId', isEqualTo: user.uid)
        .snapshots()
        .listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final doc = change.doc;
        if (_seenFallbackIds.contains(doc.id)) continue;
        _seenFallbackIds.add(doc.id);
        final d = doc.data();
        if (d == null) continue;
        if (d['isRead'] == true) continue;
        final createdAt = d['createdAt'];
        if (createdAt is Timestamp &&
            DateTime.now().difference(createdAt.toDate()).inMinutes > 2) {
          continue;
        }
        _showHeadsUpNotification(
          d['title']?.toString() ?? '',
          d['body']?.toString() ?? '',
          d['type']?.toString() ?? 'general',
          Map<String, dynamic>.from(d['data'] as Map? ?? const {}),
        );
      }
    });
    debugPrint('[OS] firestore fallback active (push denied)');
  }

  Future<bool> deleteNotification(String notifId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;
      final doc = await _db.collection('notifications').doc(notifId).get();
      if (!doc.exists) return false;
      final data = doc.data();
      if (data == null || data['userId'] != user.uid) return false;
      await _db.collection('notifications').doc(notifId).delete();
      return true;
    } catch (e) {
      debugPrint('deleteNotification: $e');
      return false;
    }
  }
}
