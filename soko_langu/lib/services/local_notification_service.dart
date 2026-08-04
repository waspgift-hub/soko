import 'dart:convert';
import 'dart:ui' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationService {
  static final LocalNotificationService _instance = LocalNotificationService._();
  factory LocalNotificationService() => _instance;
  LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Routes local heads-up taps to the same handlers OneSignal uses.
  static void Function(Map<String, dynamic> data)? onTap;

  Future<void> initialize() async {
    if (_initialized) return;
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _plugin.initialize(settings: initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
      onDidReceiveBackgroundNotificationResponse: _onBackgroundNotificationTap,
    );
    await _createChannels();
    _initialized = true;
  }

  void _onNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      if (response.actionId != null) data['action'] = response.actionId;
      onTap?.call(data);
    } catch (_) {
      // malformed payload — ignore
    }
  }

  @pragma('vm:entry-point')
  static void _onBackgroundNotificationTap(NotificationResponse response) {
    // background tap handler
  }

  Future<void> _createChannels() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    await android.createNotificationChannel(const AndroidNotificationChannel(
      'general_notifications_v5',
      'Soko Vibe',
      description: 'Flash sale, announcements, alerts, ride notifications',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
    ));
    await android.createNotificationChannel(const AndroidNotificationChannel(
      'payments_notifications_v5',
      'Payments',
      description: 'Malipo, escrow, payout, refund, KYC updates',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
    ));
    await android.createNotificationChannel(const AndroidNotificationChannel(
      'chat_messages_v5',
      'Chat Messages',
      description: 'New message notifications from chats',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
    ));
    await android.createNotificationChannel(const AndroidNotificationChannel(
      'ride_notifications_v5',
      'Ride Updates',
      description: 'Ride requests, cancellations, trip updates',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
    ));
    await android.createNotificationChannel(const AndroidNotificationChannel(
      'system_alerts_v5',
      'System Alerts',
      description: 'Account security, suspension, verification alerts',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
    ));
  }

  Future<void> showHeadsUp({
    required int id,
    required String title,
    required String body,
    String channelId = 'general_notifications_v5',
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
      ledColor: Color(0xFF2196F3),
      ledOnMs: 1000,
      ledOffMs: 500,
      channelShowBadge: true,
      actions: actions,
    );

    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(android: androidDetails),
      payload: payload,
    );
  }

  String _channelName(String channelId) {
    switch (channelId) {
      case 'chat_messages_v5':
        return 'Chat Messages';
      case 'payments_notifications_v5':
        return 'Payments';
      case 'ride_notifications_v5':
        return 'Ride Updates';
      case 'system_alerts_v5':
        return 'System Alerts';
      default:
        return 'Soko Vibe';
    }
  }
}
