import 'dart:async';
import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui' show Color;

class LocalNotificationService {
  static final LocalNotificationService _instance =
      LocalNotificationService._();

  factory LocalNotificationService() => _instance;

  LocalNotificationService._();

  static const String _pendingTapKey = 'pending_local_notification_tap';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Routes local notification taps to the same handlers OneSignal uses.
  static void Function(Map<String, dynamic> data)? onTap;

  static int _idCounter = 0;

  static int nextNotificationId() {
    if (_idCounter == 0) {
      _idCounter = DateTime.now().millisecondsSinceEpoch % 100000000;
    }
    return ++_idCounter;
  }

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@drawable/ic_notification');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
      onDidReceiveBackgroundNotificationResponse:
          _onBackgroundNotificationTap,
    );

    await _createChannels();
    _initialized = true;
  }

  Future<void> consumePendingTap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingTapKey);
    if (raw == null || raw.isEmpty) return;

    await prefs.remove(_pendingTapKey);

    try {
      final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      onTap?.call(data);
    } catch (_) {
      // Malformed persisted notification payload — ignore.
    }
  }

  void _onNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;

    try {
      final data = Map<String, dynamic>.from(jsonDecode(payload) as Map);
      final action = response.actionId;
      if (action != null && action.isNotEmpty) {
        data['action'] = action;
      }
      onTap?.call(data);
    } catch (_) {
      // Malformed payload — ignore.
    }
  }

  @pragma('vm:entry-point')
  static void _onBackgroundNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;

    unawaited(
      SharedPreferences.getInstance().then((prefs) async {
        try {
          final data = Map<String, dynamic>.from(
            jsonDecode(payload) as Map,
          );
          final action = response.actionId;
          if (action != null && action.isNotEmpty) {
            data['action'] = action;
          }
          await prefs.setString(_pendingTapKey, jsonEncode(data));
        } catch (_) {
          // Ignore malformed background payloads.
        }
      }),
    );
  }

  Future<void> _createChannels() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (android == null) return;

    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        'general_notifications_v6',
        'Soko Vibe',
        description: 'Flash sale, announcements, alerts',
        importance: Importance.max,
        enableVibration: true,
        playSound: true,
      ),
    );

    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        'payments_notifications_v6',
        'Payments',
        description: 'Malipo, escrow, payout, refund, KYC updates',
        importance: Importance.max,
        enableVibration: true,
        playSound: true,
      ),
    );

    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        'chat_messages_v6',
        'Chat Messages',
        description: 'New message notifications from chats',
        importance: Importance.max,
        enableVibration: true,
        playSound: true,
      ),
    );

    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        'system_alerts_v6',
        'System Alerts',
        description: 'Account security, suspension, verification alerts',
        importance: Importance.max,
        enableVibration: true,
        playSound: true,
      ),
    );
  }

  Future<void> showHeadsUp({
    required int id,
    required String title,
    required String body,
    String channelId = 'general_notifications_v6',
    String? payload,
    List<AndroidNotificationAction> actions = const [],
  }) async {
    final androidDetails = AndroidNotificationDetails(
      channelId,
      _channelName(channelId),
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      visibility: NotificationVisibility.public,
      showWhen: true,
      enableLights: true,
      ledColor: const Color(0xFF00C853),
      ledOnMs: 1000,
      ledOffMs: 500,
      channelShowBadge: true,
      actions: actions,
    );

    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: androidDetails,
      ),
      payload: payload,
    );
  }

  String _channelName(String channelId) {
    switch (channelId) {
      case 'chat_messages_v6':
        return 'Chat Messages';
      case 'payments_notifications_v6':
        return 'Payments';
      case 'system_alerts_v6':
        return 'System Alerts';
      default:
        return 'Soko Vibe';
    }
  }
}
