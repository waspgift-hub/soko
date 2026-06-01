import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';

final Int64List localHighVibrationPattern =
    Int64List.fromList([0, 200, 100, 200, 100, 300]);

int _notifIdCounter = 0;
int get _nextId => ++_notifIdCounter;

class NotificationService {
  static const String _key = 'push_notifications_enabled';
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  static void Function(Map<String, dynamic> data)? onNotificationTap;
  static void Function(Map<String, dynamic> data)? onPriceDropTap;

  static Future<void> initLocalNotifications() async {
    await AwesomeNotifications().initialize(
      null,
      [
        NotificationChannel(
          channelKey: 'chat_messages_v3',
          channelName: 'Chat Messages',
          channelDescription: 'New message notifications from chats',
          defaultColor: const Color(0xFF40916C),
          ledColor: const Color(0xFF40916C),
          importance: NotificationImportance.Max,
          channelShowBadge: true,
          playSound: true,
          // Samsung/Android can be strict about sound resources.
          // If you don't have this file in android/app/src/main/res/raw,
          // the safest option is to omit soundSource.
          // soundSource: 'resource://raw/soko_notification',
          vibrationPattern: localHighVibrationPattern,
          enableVibration: true,
          enableLights: true,
          defaultPrivacy: NotificationPrivacy.Public,
        ),
        NotificationChannel(
          channelKey: 'general_notifications_v3',
          channelName: 'Soko Langu',
          channelDescription: 'Flash sale, price drop & other notifications',
          defaultColor: const Color(0xFF40916C),
          ledColor: const Color(0xFF40916C),
          importance: NotificationImportance.Max,
          channelShowBadge: true,
          playSound: true,
          // soundSource: 'resource://raw/soko_notification',
          vibrationPattern: localHighVibrationPattern,
          enableVibration: true,
          enableLights: true,
        ),
      ],
    );

    await requestNotificationPermission();
  }

  static Future<void> requestNotificationPermission() async {
    await AwesomeNotifications().requestPermissionToSendNotifications();
  }

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? true;
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }

  Future<void> initialize() async {
    try {
      if (!await isEnabled()) return;

      await initLocalNotifications();

      NotificationSettings settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        criticalAlert: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        final token = await _fcm.getToken();
        if (token != null) await _saveToken(token);

        _fcm.onTokenRefresh.listen(_saveToken);

        _auth.authStateChanges().listen((user) async {
          if (user != null) {
            final t = await _fcm.getToken();
            if (t != null) await _saveToken(t);
          }
        });

        FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
        FirebaseMessaging.onBackgroundMessage(notificationBackgroundHandler);
        FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
        final initialMsg = await _fcm.getInitialMessage();
        if (initialMsg != null) {
          _handleNotificationTap(initialMsg);
        }

        await AwesomeNotifications().setListeners(
          onActionReceivedMethod: (ReceivedAction receivedAction) async {
            final rawPayload = receivedAction.payload;
            if (rawPayload == null) return;
            try {
              final data = Map<String, dynamic>.from(rawPayload);
              if (data['type'] == 'price_drop' && onPriceDropTap != null) {
                onPriceDropTap!(data);
              } else if (onNotificationTap != null) {
                onNotificationTap!(data);
              }
            } catch (_) {}
          },
        );
      }
    } catch (e) {
      debugPrint('Notification init: $e');
    }
  }

  Future<void> _saveToken(String token) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _db.collection("users").doc(user.uid).set({
      'fcmToken': token,
      'email': user.email,
    }, SetOptions(merge: true));
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final data = message.data;

    if (data['type'] == 'chat' || data['type'] == 'group_chat') {
      final senderName = data['senderName'] ?? 'New message';
      final body = message.notification?.body ?? data['body'] ?? '';
      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: _nextId,
          channelKey: 'chat_messages_v3',
          title: senderName,
          body: body,
          displayOnForeground: true,
          displayOnBackground: true,
          fullScreenIntent: true,
          payload: data.map((k, v) => MapEntry(k, v?.toString())),
          wakeUpScreen: true,
          locked: true,
          autoDismissible: false,
        ),
      );
      return;
    }

    final title = message.notification?.title ?? data['title'] as String? ?? '';
    final body = message.notification?.body ?? data['body'] as String? ?? '';
    if (title.isNotEmpty) {
      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: _nextId,
          channelKey: 'general_notifications_v3',
          title: title,
          body: body,
          displayOnForeground: true,
          displayOnBackground: true,
          fullScreenIntent: true,
          payload: data.map((k, v) => MapEntry(k, v?.toString())),
          wakeUpScreen: true,
        ),
      );
    }
  }

  void _handleNotificationTap(RemoteMessage message) {
    final data = message.data;
    if (data['type'] == 'price_drop' && onPriceDropTap != null) {
      onPriceDropTap!(data);
    } else if (onNotificationTap != null) {
      onNotificationTap!(data);
    }
  }

  // =========================
  // 📤 SEND PUSH NOTIFICATION
  // =========================
  Future<void> sendNotification({
    required String userId,
    required String title,
    String body = '',
    Map<String, String> data = const {},
  }) async {
    try {
      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/send-notification'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': userId,
          'title': title,
          'body': body,
          'data': data,
        }),
      );
    } catch (e) {
      debugPrint('sendNotification: $e');
    }
  }

  // =========================
  // 📥 STREAM IN-APP NOTIFICATIONS
  // =========================
  Stream<List<Map<String, dynamic>>> getNotifications() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);
    return _db
        .collection('notifications')
        .where('userId', isEqualTo: user.uid)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList()
            ..sort((a, b) {
              final ta = a['createdAt'];
              final tb = b['createdAt'];
              if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
              return 0;
            }),
        );
  }

  Future<void> markAsRead(String notifId) async {
    try {
      await _db.collection('notifications').doc(notifId).update({
        'isRead': true,
      });
    } catch (e) {
      debugPrint('markAsRead: $e');
    }
  }

  Future<void> markAllAsRead() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final snap = await _db
        .collection('notifications')
        .where('userId', isEqualTo: user.uid)
        .where('isRead', isEqualTo: false)
        .get();
    final batch = _db.batch();
    for (var doc in snap.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }
}

// ============================================================
// 📥 BACKGROUND HANDLER — must be top-level function for firebase_messaging
// ============================================================
int _bgNotifIdCounter = 0;

@pragma('vm:entry-point')
Future<void> notificationBackgroundHandler(RemoteMessage message) async {
  try {
    await AwesomeNotifications().initialize(null, []);

    final data = message.data;
    final title = message.notification?.title ?? data['title'] ?? '';
    final body = message.notification?.body ?? data['body'] ?? '';
    if (title.isEmpty) return;

    final isChat = data['type'] == 'chat' || data['type'] == 'group_chat';
    final nid = ++_bgNotifIdCounter;

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: nid,
        channelKey: isChat ? 'chat_messages_v3' : 'general_notifications_v3',
        title: isChat ? (data['senderName'] ?? 'New message') : title,
        body: body,
        displayOnBackground: true,
        fullScreenIntent: true,
        payload: data.map((k, v) => MapEntry(k, v?.toString())),
        wakeUpScreen: true,
      ),
    );
  } catch (e) {
    debugPrint('Background handler error: $e');
  }
}
