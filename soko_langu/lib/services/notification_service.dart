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

        OneSignal.Notifications.addForegroundWillDisplayListener((event) {
          final notif = event.notification;
          final data = notif.additionalData ?? {};
          final title = notif.title ?? '';
          final body = notif.body ?? '';
          final type = data['type'] as String? ?? 'general';

          debugPrint('[OS] foreground notification: type=$type title=$title');

          event.preventDefault();

          final String channelId;
          final String? payload;
          final int id;
          final String headsUpTitle;

          if (type == 'chat' || type == 'group_chat') {
            final roomId = data['roomId'] as String? ?? '';
            channelId = 'chat_messages_v5';
            id = roomId.hashCode;
            headsUpTitle = data['senderName'] as String? ?? title;
            payload = '/chat/$roomId';
          } else if (type == 'payment' || type == 'order') {
            final orderId = data['orderId'] as String?;
            channelId = 'payments_notifications_v5';
            id = (orderId ?? title).hashCode;
            headsUpTitle = title;
            payload = orderId != null ? '/order-detail/$orderId' : null;
          } else {
            channelId = 'general_notifications_v5';
            id = title.hashCode;
            headsUpTitle = title;
            payload = null;
          }

          LocalNotificationService().showHeadsUp(
            id: id,
            title: headsUpTitle,
            body: body,
            channelId: channelId,
            payload: payload,
          );

          if (title.isNotEmpty && onForegroundMessage != null) {
            onForegroundMessage!(title, body, type, data);
          }
        });

        OneSignal.Notifications.addClickListener((event) {
          final data = event.notification.additionalData ?? {};
          debugPrint('[OS] notification tapped: type=${data['type']}');
          _onNotificationTapped(data);
        });

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

  /// Register user's email with OneSignal for email notifications
  Future<void> registerEmail(String email) async {
    try {
      OneSignal.User.addEmail(email);
      debugPrint('[OS] registered email: $email');
    } catch (e) {
      debugPrint('[OS] registerEmail error: $e');
    }
  }

  /// Remove email subscription from OneSignal
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
