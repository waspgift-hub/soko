import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
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

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _initialized = false;
  bool _listenersRegistered = false;

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
        NotificationPermission.Vibration,
        NotificationPermission.Sound,
        NotificationPermission.Alert,
        NotificationPermission.Light,
        NotificationPermission.FullScreenIntent,
      ],
    );
    debugPrint('[OS] Permission result: allowed=$allowed');
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
      OneSignal.Notifications.clearAll();
      await OneSignal.logout();
    }
  }

  Future<void> initialize() async {
    try {
      if (!await isEnabled()) {
        debugPrint('[OS] notifications disabled by user preference');
        return;
      }

      if (_initialized) return;
      _initialized = true;

      OneSignal.initialize(ApiConfig.oneSignalAppId);

      final user = _auth.currentUser;
      if (user != null) {
        OneSignal.login(user.uid);
        debugPrint('[OS] logged in user ${user.uid}');
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
          FcmNotificationDisplay.showFromMap({
            'title': title,
            'body': body,
            ...data,
          });

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
          } else {
            await OneSignal.logout();
            debugPrint('[OS] auth change — logged out');
          }
        });

        await AwesomeNotifications().setListeners(
          onActionReceivedMethod: (ReceivedAction receivedAction) async {
            final rawPayload = receivedAction.payload;
            if (rawPayload != null) _onNotificationTapped(rawPayload);
          },
        );
        debugPrint('[OS] handlers registered');
      }

      await initLocalNotifications();

      debugPrint('[OS] initialized');
    } catch (e) {
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
