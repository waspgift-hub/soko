import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'local_notification_service.dart';

class NotificationService {
  static const String _key = 'push_notifications_enabled';

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _initialized = false;
  bool _listenersRegistered = false;

  final StreamController<int> _unreadController = StreamController<int>.broadcast();
  Stream<int> get unreadCountStream => _unreadController.stream;

  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  static void Function(Map<String, dynamic> data)? onNotificationTap;
  static void Function(Map<String, dynamic> data)? onPaymentNotificationTap;
  static void Function(String title, String body, String type, Map<String, dynamic>? data)? onForegroundMessage;

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

      OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
      OneSignal.initialize(ApiConfig.oneSignalAppId);

      final perm = await OneSignal.Notifications.requestPermission(true);
      debugPrint('[OS] permission result: $perm');

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
        _listenersRegistered = true;

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
          } else {
            await OneSignal.logout();
            debugPrint('[OS] auth change — logged out');
          }
        });

        debugPrint('[OS] handlers registered');
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
    final String? payload;
    final String headsUpTitle;

    switch (type) {
      case 'chat':
      case 'group_chat':
        final roomId = data['roomId'] as String? ?? '';
        channelId = 'chat_messages_v5';
        headsUpTitle = data['senderName'] as String? ?? title;
        payload = '/chat/$roomId';
        break;
      case 'payment':
      case 'order':
      case 'kyc':
      case 'kyc_approved':
      case 'kyc_rejected':
      case 'kyc_revoked':
        final orderId = data['orderId'] as String?;
        channelId = 'payments_notifications_v5';
        headsUpTitle = title;
        payload = orderId != null ? '/order-detail/$orderId' : null;
        break;
      case 'ride':
      case 'ride_request':
      case 'ride_accepted':
      case 'ride_completed':
        channelId = 'general_notifications_v5';
        headsUpTitle = title;
        payload = '/ride';
        break;
      case 'boost':
      case 'promotion':
        channelId = 'general_notifications_v5';
        headsUpTitle = title;
        payload = '/my-ads';
        break;
      case 'system':
      case 'admin':
      case 'alert':
        channelId = 'system_alerts_v5';
        headsUpTitle = title;
        payload = null;
        break;
      default:
        channelId = 'general_notifications_v5';
        headsUpTitle = title;
        payload = null;
    }

    final bool isCritical = type == 'system' || type == 'admin' || type == 'alert' ||
        type == 'payment' || type == 'order' || type == 'chat' || type == 'ride_request';

    LocalNotificationService().showHeadsUp(
      id: DateTime.now().millisecondsSinceEpoch % 2147483647,
      title: headsUpTitle,
      body: body,
      channelId: channelId,
      payload: payload,
      fullScreen: isCritical,
    );

    if (title.isNotEmpty && onForegroundMessage != null) {
      onForegroundMessage!(title, body, type, data);
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
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/send-notification'),
        headers: {'Content-Type': 'application/json'},
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
