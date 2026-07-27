import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationService {
  static final LocalNotificationService _instance = LocalNotificationService._();
  factory LocalNotificationService() => _instance;
  LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _plugin.initialize(settings: initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );
    await _createChannels();
    _initialized = true;
  }

  void _onNotificationTap(NotificationResponse response) {
    // payload is handled by OneSignal click listener
  }

  Future<void> _createChannels() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    // Delete old v4 channels so v5 channels take effect without reinstall
    for (final oldId in ['general_notifications_v4', 'chat_messages_v4', 'payments_notifications_v4']) {
      try { await android.deleteNotificationChannel(oldId); } catch (_) {}
    }
    await android.createNotificationChannel(const AndroidNotificationChannel(
      'general_notifications_v5',
      'Soko Vibe',
      description: 'Flash sale, announcements, alerts',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
    ));
    await android.createNotificationChannel(const AndroidNotificationChannel(
      'payments_notifications_v5',
      'Payments',
      description: 'Malipo, escrow, payout, refund',
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
  }

  Future<void> showHeadsUp({
    required int id,
    required String title,
    required String body,
    String channelId = 'general_notifications_v5',
    String? payload,
  }) async {
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          _channelName(channelId),
          importance: Importance.max,
          priority: Priority.max,
          fullScreenIntent: true,
          playSound: true,
          enableVibration: true,
          category: AndroidNotificationCategory.alarm,
        ),
      ),
      payload: payload,
    );
  }

  String _channelName(String channelId) {
    switch (channelId) {
      case 'chat_messages_v5':
        return 'Chat Messages';
      case 'payments_notifications_v5':
        return 'Payments';
      default:
        return 'Soko Vibe';
    }
  }
}
