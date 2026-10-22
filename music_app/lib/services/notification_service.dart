import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Local notifications for daily listening reminders and important app events.
/// Call initialize() once during app startup, then requestPermission() after
/// an explicit user-facing action/onboarding.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel importantChannel =
      AndroidNotificationChannel(
    'sokovibe_important',
    'Important updates',
    description: 'Playback, downloads and account-related updates.',
    importance: Importance.high,
  );

  static const AndroidNotificationChannel reminderChannel =
      AndroidNotificationChannel(
    'sokovibe_daily_reminder',
    'Daily listening reminder',
    description: 'A gentle daily reminder to enjoy music.',
    importance: Importance.defaultImportance,
  );

  Future<void> initialize() async {
    tzdata.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings);
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(importantChannel);
    await androidPlugin?.createNotificationChannel(reminderChannel);
  }

  Future<bool> requestPermission() async {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await androidPlugin?.requestNotificationsPermission() ?? false;
  }

  /// Schedules a repeating daily reminder at the user's chosen local time.
  /// Android may defer exact delivery due to battery/OS policies.
  Future<void> scheduleDailyReminder({
    int hour = 19,
    int minute = 0,
    bool enabled = true,
  }) async {
    if (!enabled) {
      await cancelDailyReminder();
      return;
    }
    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, hour, minute);
    if (!next.isAfter(now)) {
      next = next.add(const Duration(days: 1));
    }
    await _plugin.zonedSchedule(
      1001,
      'Time for your music 🎵',
      'Take a break and discover something you love on Soko Vibe Music.',
      next,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'sokovibe_daily_reminder',
          'Daily listening reminder',
          channelDescription: 'A gentle daily reminder to enjoy music.',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'open_music',
    );
  }

  Future<void> cancelDailyReminder() => _plugin.cancel(1001);

  Future<void> showImportant({
    required String title,
    required String body,
    String? payload,
    int id = 2001,
  }) async {
    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'sokovibe_important',
          'Important updates',
          channelDescription:
              'Playback, downloads and account-related updates.',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload: payload,
    );
  }

  Future<void> notifyPlaybackFailed() => showImportant(
        id: 2002,
        title: 'Could not play this song',
        body: 'Check your connection and try again.',
        payload: 'retry_playback',
      );

  Future<void> notifyDownloadComplete(String name) => showImportant(
        id: 2003,
        title: 'Download complete',
        body: name,
        payload: 'open_downloads',
      );

  Future<void> notifyAccountUpdate(String message) => showImportant(
        id: 2004,
        title: 'Account update',
        body: message,
        payload: 'open_account',
      );
}