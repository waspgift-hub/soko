import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'fcm_notification_display.dart';

final Int64List localHighVibrationPattern =
    Int64List.fromList([0, 200, 100, 200, 100, 300]);

class NotificationService {
  static const String _key = 'push_notifications_enabled';
  static const String customSound = 'resource://raw/soko_notification';

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _handlersRegistered = false;

  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  static void Function(Map<String, dynamic> data)? onNotificationTap;
  static void Function(Map<String, dynamic> data)? onPaymentNotificationTap;
  static void Function(String title, String body, String type, Map<String, dynamic>? data)? onForegroundMessage;

  static List<NotificationChannel> get channels => _channels;

  static List<NotificationChannel> get _channels => [
        NotificationChannel(
          channelKey: 'chat_messages_v4',
          channelName: 'Chat Messages',
          channelDescription: 'New message notifications from chats',
          defaultColor: const Color(0xFF40916C),
          ledColor: const Color(0xFF40916C),
          importance: NotificationImportance.Max,
          channelShowBadge: true,
          playSound: true,
          soundSource: customSound,
          vibrationPattern: localHighVibrationPattern,
          enableVibration: true,
          enableLights: true,
          defaultPrivacy: NotificationPrivacy.Public,
        ),
        NotificationChannel(
          channelKey: 'general_notifications_v4',
          channelName: 'Soko Vibe',
          channelDescription: 'Flash sale & other notifications',
          defaultColor: const Color(0xFF40916C),
          ledColor: const Color(0xFF40916C),
          importance: NotificationImportance.Max,
          channelShowBadge: true,
          playSound: true,
          soundSource: customSound,
          vibrationPattern: localHighVibrationPattern,
          enableVibration: true,
          enableLights: true,
        ),
        NotificationChannel(
          channelKey: 'payments_notifications_v4',
          channelName: 'Payments',
          channelDescription: 'Notifications for payment transactions',
          defaultColor: const Color(0xFF2D6A4F),
          ledColor: const Color(0xFF2D6A4F),
          importance: NotificationImportance.Max,
          channelShowBadge: true,
          playSound: true,
          soundSource: customSound,
          vibrationPattern: localHighVibrationPattern,
          enableVibration: true,
          enableLights: true,
        ),
      ];

  static Future<void> initLocalNotifications() async {
    await AwesomeNotifications().initialize(
      'resource://drawable/ic_notification',
      channels,
    );
    await requestNotificationPermission();
  }

  static Future<void> requestNotificationPermission() async {
    final allowed = await AwesomeNotifications().requestPermissionToSendNotifications(
      permissions: [
        NotificationPermission.Vibrate,
        NotificationPermission.Sound,
        NotificationPermission.Alert,
        NotificationPermission.Light,
        NotificationPermission.FullScreenIntent,
      ],
    );
    debugPrint('[FCM] Permission result: allowed=$allowed');
  }

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? true;
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
    if (value) {
      await initialize();
    } else {
      await _clearToken();
    }
  }

  Future<void> initialize() async {
    try {
      if (!await isEnabled()) {
        debugPrint('[FCM] notifications disabled by user preference');
        return;
      }

      await initLocalNotifications();

      if (!kIsWeb) {
        final settings = await _fcm.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          criticalAlert: true,
          provisional: false,
        );
        debugPrint('[FCM] requestPermission status: ${settings.authorizationStatus}');
      }

      if (!_handlersRegistered) {
        _handlersRegistered = true;
        FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
        FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
        _fcm.onTokenRefresh.listen(_saveAndSubscribe);
        _auth.authStateChanges().listen((user) async {
          if (user != null && await isEnabled()) {
            final t = await _fcm.getToken();
            if (t != null) {
              debugPrint('[FCM] auth change — saving token for ${user.uid}');
              await _saveAndSubscribe(t);
            }
          } else if (user == null) {
            debugPrint('[FCM] user logged out — no token cleanup needed');
          }
        });
        await AwesomeNotifications().setListeners(
          onActionReceivedMethod: (ReceivedAction receivedAction) async {
            final rawPayload = receivedAction.payload;
            if (rawPayload != null) _onNotificationTapped(rawPayload);
          },
        );
        debugPrint('[FCM] handlers registered');
      }

      final token = await _fcm.getToken();
      if (token != null) {
        debugPrint('[FCM] current token: ${token.substring(0, 20)}...');
        await _saveAndSubscribe(token);
      } else {
        debugPrint('[FCM] no token available');
      }

      final user = _auth.currentUser;
      if (user != null) {
        try {
          await _fcm.subscribeToTopic('user_${user.uid}');
          debugPrint('[FCM] subscribed to topic user_${user.uid}');
        } catch (e) {
          debugPrint('[FCM] topic subscribe failed: $e');
        }
      }

      final initialMsg = await _fcm.getInitialMessage();
      if (initialMsg != null) {
        debugPrint('[FCM] initial message: type=${initialMsg.data['type']}');
        _handleNotificationTap(initialMsg);
      }
    } catch (e) {
      debugPrint('[FCM] Notification init error: $e');
    }
  }

  Future<void> _clearToken() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await _db.collection('users').doc(user.uid).set(
          {'fcmToken': FieldValue.delete()},
          SetOptions(merge: true),
        );
        debugPrint('[FCM] token cleared from Firestore for ${user.uid}');
      }
      await _fcm.deleteToken();
      debugPrint('[FCM] local token deleted');
    } catch (e) {
      debugPrint('[FCM] token clear error: $e');
    }
  }

  Future<void> _saveAndSubscribe(String token) async {
    if (!await isEnabled()) return;
    final user = _auth.currentUser;
    if (user == null) {
      debugPrint('[FCM] _saveAndSubscribe: no user');
      return;
    }
    await _db.collection('users').doc(user.uid).set({
      'fcmToken': token,
      'email': user.email,
    }, SetOptions(merge: true));
    debugPrint('[FCM] token saved to Firestore for ${user.uid}');
    try {
      await _fcm.subscribeToTopic('user_${user.uid}');
    } catch (e) {
      debugPrint('[FCM] topic subscribe failed: $e');
    }
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    if (!await isEnabled()) return;
    debugPrint('[FCM] foreground message: type=${message.data['type']} hasNotification=${message.notification != null}');
    await FcmNotificationDisplay.show(message);
    final data = message.data;
    final title = message.notification?.title ?? data['title'] as String? ?? '';
    final body = message.notification?.body ?? data['body'] as String? ?? '';
    final type = data['type'] as String? ?? 'general';
    if (title.isNotEmpty && onForegroundMessage != null) {
      onForegroundMessage!(title, body, type, data);
    }
  }

  void _handleNotificationTap(RemoteMessage message) {
    debugPrint('[FCM] notification tapped: type=${message.data['type']}');
    _onNotificationTapped(message.data);
  }

  static void _onNotificationTapped(Map<String, dynamic> data) {
    debugPrint('[FCM] _onNotificationTapped: type=${data['type']}');
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
      debugPrint('[FCM] sendNotification to $userId: $title');
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
      debugPrint('[FCM] sendNotification response: ${response.statusCode}');
    } catch (e) {
      debugPrint('[FCM] sendNotification error: $e');
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
          (snap) => snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList()
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
