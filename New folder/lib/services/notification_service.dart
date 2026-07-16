import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'api_config.dart';
import '../firebase_options.dart';

final FlutterLocalNotificationsPlugin localNotifications =
    FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.initLocalNotifications();
  await NotificationService.handleBackgroundMessage(message);
}

class NotificationService {
  static const String _key = 'push_notifications_enabled';
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  static void Function(Map<String, dynamic> data)? onCallNotificationTap;
  static void Function(Map<String, dynamic> data)? onForegroundCall;
  static void Function(String callId)? onCallAcceptFromNotification;
  static void Function(String callId)? onCallDeclineFromNotification;
  static void Function(Map<String, dynamic> data)? onOrderNotificationTap;
  static void Function(Map<String, dynamic> data)? onOrderMessageTap;
  static void Function(Map<String, dynamic> data)? onPaymentNotificationTap;

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
          if (response.actionId == 'accept_call') {
            onCallAcceptFromNotification?.call(data['callId'] as String);
          } else if (response.actionId == 'decline_call') {
            onCallDeclineFromNotification?.call(data['callId'] as String);
          } else if (response.actionId == 'message_buyer') {
            onOrderMessageTap?.call(data);
          } else if (response.actionId == 'view_order') {
            onOrderNotificationTap?.call(data);
          } else {
            if (data['type'] == 'order') {
              onOrderNotificationTap?.call(data);
            } else if (data['type'] == 'payment') {
              onPaymentNotificationTap?.call(data);
            } else {
              onCallNotificationTap?.call(data);
            }
          }
        } catch (_) {}
      },
    );

    final callChannel = AndroidNotificationChannel(
      'incoming_calls_v2',
      'Incoming Calls',
      description: 'Notifications for incoming voice and video calls',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      showBadge: true,
      enableLights: true,
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
    final orderChannel = AndroidNotificationChannel(
      'order_notifications',
      'Orders',
      description: 'Notifications for new orders',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      showBadge: true,
      enableLights: true,
    );
    final paymentsChannel = AndroidNotificationChannel(
      'payments_notifications',
      'Payments',
      description: 'Notifications for payment transactions',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      showBadge: true,
      enableLights: true,
    );
    final generalChannel = AndroidNotificationChannel(
      'general_notifications',
      'General',
      description: 'Other app notifications',
      importance: Importance.defaultImportance,
      playSound: true,
      enableVibration: true,
      showBadge: false,
      enableLights: false,
    );
    final missedCallsChannel = AndroidNotificationChannel(
      'missed_calls_v2',
      'Missed Calls',
      description: 'Notifications for missed calls',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      showBadge: true,
      enableLights: true,
    );
    final plugin = localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await plugin?.createNotificationChannel(callChannel);
    await plugin?.createNotificationChannel(chatChannel);
    await plugin?.createNotificationChannel(orderChannel);
    await plugin?.createNotificationChannel(paymentsChannel);
    await plugin?.createNotificationChannel(generalChannel);
    await plugin?.createNotificationChannel(missedCallsChannel);
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
        FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
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

  static Future<void> handleBackgroundMessage(RemoteMessage message) async {
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
      return;
    }
    if (data['type'] == 'order') {
      final title = message.notification?.title ?? 'Agizo Jipya!';
      final body = message.notification?.body ?? '';
      await localNotifications.show(
        id: DateTime.now().millisecondsSinceEpoch % 100000,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'order_notifications',
            'Orders',
            channelDescription: 'Notifications for new orders',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            enableLights: true,
            actions: [
              AndroidNotificationAction(
                'message_buyer',
                'Message Buyer',
                showsUserInterface: true,
              ),
              AndroidNotificationAction(
                'view_order',
                'View Order',
                showsUserInterface: true,
              ),
            ],
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            categoryIdentifier: 'order_notification',
          ),
        ),
        payload: jsonEncode(data),
      );
      return;
    }
    if (data['type'] == 'payment') {
      final title = message.notification?.title ?? 'Payment Update';
      final body = message.notification?.body ?? '';
      await localNotifications.show(
        id: DateTime.now().millisecondsSinceEpoch % 100000,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'payments_notifications',
            'Payments',
            channelDescription: 'Notifications for payment transactions',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            enableLights: true,
            category: AndroidNotificationCategory.status,
            visibility: NotificationVisibility.public,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: jsonEncode(data),
      );
      return;
    }
      return;
    }
    if (data['type'] == 'call') {
      final callId = data['callId'] as String? ?? '';
      final callerName = data['callerName'] as String? ?? 'Incoming Call';
      final callerImage = data['callerImage'] as String? ?? '';
      final channelName = data['channelName'] as String? ?? '';
      final callType = data['callType'] as String? ?? 'voice';

      await FlutterCallkitIncoming.showCallkitIncoming(CallKitParams(
        id: callId,
        nameCaller: callerName,
        appName: 'Soko Vibe',
        avatar: callerImage.isNotEmpty ? callerImage : null,
        handle: callType == 'video' ? 'Video Call' : 'Voice Call',
        type: callType == 'video' ? 1 : 0,
        textAccept: 'Accept',
        textDecline: 'Decline',
        duration: 30000,
        missedCallNotification: const NotificationParams(
          showNotification: true,
          isShowCallback: true,
          callbackText: 'Call back',
        ),
        extra: <String, dynamic>{
          'callId': callId,
          'channelName': channelName,
          'callType': callType,
          'callerName': callerName,
          'callerImage': callerImage,
        },
        android: AndroidParams(
          isCustomNotification: true,
          isShowLogo: false,
          ringtonePath: 'system_ringtone_default',
          backgroundColor: '#0D1B12',
          backgroundUrl: null,
          actionColor: '#2D6A4F',
          textColor: '#FFFFFF',
          incomingCallNotificationChannelName: 'Incoming Calls',
          missedCallNotificationChannelName: 'Missed Calls',
          isShowCallID: false,
          isShowFullLockedScreen: true,
        ),
        ios: IOSParams(
          iconName: 'CallKitLogo',
          handleType: 'generic',
          supportsVideo: true,
          maximumCallGroups: 1,
          maximumCallsPerCallGroup: 1,
          audioSessionMode: 'default',
          audioSessionActive: true,
          audioSessionPreferredSampleRate: 44100.0,
          audioSessionPreferredIOBufferDuration: 0.005,
          supportsDTMF: false,
          supportsHolding: false,
          supportsGrouping: false,
          supportsUngrouping: false,
          ringtonePath: 'system_ringtone_default',
        ),
      ));
      return;
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

    if (data['type'] == 'payment') {
      final title = message.notification?.title ?? 'Payment Update';
      final body = message.notification?.body ?? data['body'] ?? '';
      localNotifications.show(
        id: DateTime.now().millisecondsSinceEpoch % 100000,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'payments_notifications',
            'Payments',
            channelDescription: 'Notifications for payment transactions',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            enableLights: true,
            category: AndroidNotificationCategory.status,
            visibility: NotificationVisibility.public,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: jsonEncode(data),
      );
      return;
    }

    if (data['type'] == 'order') {
      final title = message.notification?.title ?? 'Agizo Jipya!';
      final body = message.notification?.body ?? data['body'] ?? '';
      localNotifications.show(
        id: DateTime.now().millisecondsSinceEpoch % 100000,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'order_notifications',
            'Orders',
            channelDescription: 'Notifications for new orders',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            enableLights: true,
            actions: [
              AndroidNotificationAction(
                'message_buyer',
                'Message Buyer',
                showsUserInterface: true,
              ),
              AndroidNotificationAction(
                'view_order',
                'View Order',
                showsUserInterface: true,
              ),
            ],
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            categoryIdentifier: 'order_notification',
          ),
        ),
        payload: jsonEncode(data),
      );
      return;
    }

    if (data['type'] == 'call') {
      if (onForegroundCall != null) {
        onForegroundCall!(data);
      } else {
        final callId = data['callId'] as String? ?? '';
        final callerName = data['callerName'] as String? ?? 'Incoming Call';
        final callerImage = data['callerImage'] as String? ?? '';
        final channelName = data['channelName'] as String? ?? '';
        final callType = data['callType'] as String? ?? 'voice';

        await FlutterCallkitIncoming.showCallkitIncoming(CallKitParams(
          id: callId,
          nameCaller: callerName,
          appName: 'Soko Vibe',
          avatar: callerImage.isNotEmpty ? callerImage : null,
          handle: callType == 'video' ? 'Video Call' : 'Voice Call',
          type: callType == 'video' ? 1 : 0,
          textAccept: 'Accept',
          textDecline: 'Decline',
          duration: 30000,
          missedCallNotification: const NotificationParams(
            showNotification: true,
            isShowCallback: true,
            callbackText: 'Call back',
          ),
          extra: <String, dynamic>{
            'callId': callId,
            'channelName': channelName,
            'callType': callType,
            'callerName': callerName,
            'callerImage': callerImage,
          },
          android: AndroidParams(
            isCustomNotification: true,
            isShowLogo: false,
            ringtonePath: 'system_ringtone_default',
            backgroundColor: '#0D1B12',
            backgroundUrl: null,
            actionColor: '#2D6A4F',
            textColor: '#FFFFFF',
            incomingCallNotificationChannelName: 'Incoming Calls',
            missedCallNotificationChannelName: 'Missed Calls',
            isShowCallID: false,
            isShowFullLockedScreen: true,
          ),
          ios: IOSParams(
            iconName: 'CallKitLogo',
            handleType: 'generic',
            supportsVideo: true,
            maximumCallGroups: 1,
            maximumCallsPerCallGroup: 1,
            audioSessionMode: 'default',
            audioSessionActive: true,
            audioSessionPreferredSampleRate: 44100.0,
            audioSessionPreferredIOBufferDuration: 0.005,
            supportsDTMF: false,
            supportsHolding: false,
            supportsGrouping: false,
            supportsUngrouping: false,
            ringtonePath: 'system_ringtone_default',
          ),
        ));
      }
      return;
    }

    final title = message.notification?.title ?? '';
    final body = message.notification?.body ?? '';
    if (title.isNotEmpty) {
      localNotifications.show(
        id: DateTime.now().millisecondsSinceEpoch % 100000,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'general_notifications',
            'General',
            channelDescription: 'Other app notifications',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            playSound: true,
            enableVibration: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: true,
          ),
        ),
        payload: jsonEncode(data),
      );
    }
  }

  void _handleNotificationTap(RemoteMessage message) {
    final data = message.data;
    if (data['type'] == 'call' && onCallNotificationTap != null) {
      onCallNotificationTap!(data);
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
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList(),
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
