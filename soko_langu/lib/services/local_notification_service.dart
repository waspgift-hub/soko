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
    await _plugin.initialize(settings: initSettings);
    await _createChannels();
    _initialized = true;
  }

  Future<void> _createChannels() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    await android.createNotificationChannel(const AndroidNotificationChannel(
      'chat_messages_v4',
      'Chat Messages',
      description: 'New message notifications from chats',
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
    ));
    await android.createNotificationChannel(const AndroidNotificationChannel(
      'payments_notifications_v4',
      'Payments',
      description: 'Notifications for payment transactions',
      importance: Importance.high,
    ));
    await android.createNotificationChannel(const AndroidNotificationChannel(
      'general_notifications_v4',
      'Soko Vibe',
      description: 'Flash sale na notifications nyingine',
      importance: Importance.high,
    ));
  }

  Future<void> showHeadsUp({
    required int id,
    required String title,
    required String body,
    String channelId = 'general_notifications_v4',
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
          importance: Importance.high,
          priority: Priority.high,
          fullScreenIntent: true,
          playSound: true,
          enableVibration: true,
        ),
      ),
      payload: payload,
    );
  }

  String _channelName(String channelId) {
    switch (channelId) {
      case 'chat_messages_v4':
        return 'Chat Messages';
      case 'payments_notifications_v4':
        return 'Payments';
      default:
        return 'Soko Vibe';
    }
  }
}
