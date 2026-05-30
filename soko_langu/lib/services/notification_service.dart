import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'api_config.dart';

final FlutterLocalNotificationsPlugin localNotifications =
    FlutterLocalNotificationsPlugin();

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
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await localNotifications.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null) return;
        try {
          final data = jsonDecode(payload) as Map<String, dynamic>;
          onNotificationTap?.call(data);
        } catch (_) {}
      },
    );

    final chatChannel = AndroidNotificationChannel(
      'chat_messages_v2',
      'Chat Messages',
      description: 'New message notifications from chats',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      showBadge: true,
      enableLights: true,
    );
    final plugin = localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await plugin?.createNotificationChannel(chatChannel);
    await plugin?.requestNotificationsPermission();
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

        FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
        FirebaseMessaging.onBackgroundMessage(_backgroundHandler);
        FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
        final initialMsg = await _fcm.getInitialMessage();
        if (initialMsg != null) {
          _handleNotificationTap(initialMsg);
        }
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
      localNotifications.show(
        id: DateTime.now().millisecondsSinceEpoch % 100000,
        title: senderName,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'chat_messages_v2',
            'Chat Messages',
            channelDescription: 'New message notifications from chats',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            enableLights: true,
            fullScreenIntent: true,
            category: AndroidNotificationCategory.message,
            visibility: NotificationVisibility.public,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            categoryIdentifier: 'chat_message',
          ),
        ),
        payload: jsonEncode(data),
      );
      return;
    }

    final title = message.notification?.title ?? '';
    final body = message.notification?.body ?? '';
    if (title.isNotEmpty && messengerKey.currentContext != null) {
      messengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('$title\n$body'),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _handleNotificationTap(RemoteMessage message) {
    final data = message.data;
    if (data['type'] == 'price_drop' && onPriceDropTap != null) {
      onPriceDropTap!(data);
    }
  }

  static Future<void> _backgroundHandler(RemoteMessage message) async {
    final data = message.data;
    if (data['type'] == 'chat' || data['type'] == 'group_chat') {
      final senderName = data['senderName'] ?? 'New message';
      final body = message.notification?.body ?? '';
      await localNotifications.show(
        id: DateTime.now().millisecondsSinceEpoch % 100000,
        title: senderName,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'chat_messages_v2',
            'Chat Messages',
            channelDescription: 'New message notifications from chats',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            enableLights: true,
            fullScreenIntent: true,
            category: AndroidNotificationCategory.message,
            visibility: NotificationVisibility.public,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            categoryIdentifier: 'chat_message',
          ),
        ),
        payload: jsonEncode(data),
      );
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
