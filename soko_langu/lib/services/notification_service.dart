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

  static List<NotificationChannel> get channels => _channels;

  static List<NotificationChannel> get _channels => [
        NotificationChannel(
          channelKey: 'chat_messages_v3',
          channelName: 'Chat Messages',
          channelDescription: 'New message notifications from chats',
          defaultColor: const Color(0xFF40916C),
          ledColor: const Color(0xFF40916C),
          importance: NotificationImportance.High,
          channelShowBadge: true,
          playSound: true,
          soundSource: customSound,
          vibrationPattern: localHighVibrationPattern,
          enableVibration: true,
          enableLights: true,
          defaultPrivacy: NotificationPrivacy.Public,
        ),
        NotificationChannel(
          channelKey: 'general_notifications_v3',
          channelName: 'Soko Vibe',
          channelDescription: 'Flash sale & other notifications',
          defaultColor: const Color(0xFF40916C),
          ledColor: const Color(0xFF40916C),
          importance: NotificationImportance.High,
          channelShowBadge: true,
          playSound: true,
          soundSource: customSound,
          vibrationPattern: localHighVibrationPattern,
          enableVibration: true,
          enableLights: true,
        ),
        NotificationChannel(
          channelKey: 'payments_notifications',
          channelName: 'Payments',
          channelDescription: 'Notifications for payment transactions',
          defaultColor: const Color(0xFF2D6A4F),
          ledColor: const Color(0xFF2D6A4F),
          importance: NotificationImportance.High,
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
    await AwesomeNotifications().requestPermissionToSendNotifications();
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
      if (!await isEnabled()) return;

      await initLocalNotifications();

      final settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        debugPrint('FCM: display permission not granted — FCM token still saved');
      }

      if (!_handlersRegistered) {
        _handlersRegistered = true;
        FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
        FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
        _fcm.onTokenRefresh.listen(_saveToken);
        _auth.authStateChanges().listen((user) async {
          if (user != null && await isEnabled()) {
            final t = await _fcm.getToken();
            if (t != null) await _saveToken(t);
          }
        });
        await AwesomeNotifications().setListeners(
          onActionReceivedMethod: (ReceivedAction receivedAction) async {
            final rawPayload = receivedAction.payload;
            if (rawPayload != null) _onNotificationTapped(rawPayload);
          },
        );
      }

      final token = await _fcm.getToken();
      if (token != null) await _saveToken(token);

      final initialMsg = await _fcm.getInitialMessage();
      if (initialMsg != null) _handleNotificationTap(initialMsg);
    } catch (e) {
      debugPrint('Notification init: $e');
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
      }
      await _fcm.deleteToken();
    } catch (e) {
      debugPrint('FCM token clear: $e');
    }
  }

  Future<void> _saveToken(String token) async {
    if (!await isEnabled()) return;
    final user = _auth.currentUser;
    if (user == null) return;
    await _db.collection('users').doc(user.uid).set({
      'fcmToken': token,
      'email': user.email,
    }, SetOptions(merge: true));
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    if (!await isEnabled()) return;
    await FcmNotificationDisplay.show(message);
  }

  void _handleNotificationTap(RemoteMessage message) {
    _onNotificationTapped(message.data);
  }

  static void _onNotificationTapped(Map<String, dynamic> data) {
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
