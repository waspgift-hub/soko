import 'dart:ui' show Color;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import 'notification_channels.dart';
import 'notification_heads_up.dart';

/// Posts local heads-up notifications and routes their taps into app navigation.
class LocalNotificationService {
  static final LocalNotificationService _instance = LocalNotificationService._();
  factory LocalNotificationService() => _instance;
  LocalNotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// Last observed POST_NOTIFICATIONS state. Null until Android has been asked.
  static bool? _granted;

  /// Last known POST_NOTIFICATIONS value, for UI that needs a cached answer.
  static bool? get granted => _granted;

  /// Routes local heads-up taps to the same handlers OneSignal uses.
  static void Function(Map<String, dynamic> data)? onTap;

  static Map<String, dynamic>? _pendingTap;

  /// Payload held when a notification launched the app before handlers existed.
  @visibleForTesting
  static Map<String, dynamic>? get pendingTap => _pendingTap;

  /// Installs [handler] and immediately drains a tap captured before it existed.
  static void setTapHandler(void Function(Map<String, dynamic> data)? handler) {
    onTap = handler;
    final pending = _pendingTap;
    if (handler == null || pending == null) return;
    _pendingTap = null;
    handler(pending);
  }

  /// Checks POST_NOTIFICATIONS against the OS on every call.
  ///
  /// Android 13+ silently drops `show()` without this permission, so a cached
  /// "yes" would let a user who revoked access in settings miss real alerts.
  static Future<bool> hasPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    try {
      _granted = await android.areNotificationsEnabled() ?? false;
    } catch (_) {
      _granted = null;
    }
    return _granted ?? false;
  }

  /// Asks for POST_NOTIFICATIONS on Android 13+ and records the result.
  static Future<bool> requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    try {
      _granted = await android.requestNotificationsPermission() ?? false;
    } catch (_) {
      _granted = null;
    }
    debugPrint('[NOTIF] POST_NOTIFICATIONS granted=$_granted');
    return _granted ?? false;
  }

  /// Opens this app's notification settings after a permanent OS denial.
  static Future<void> openSystemSettings() async {
    try {
      await openAppSettings();
    } catch (e) {
      debugPrint('[NOTIF] openAppSettings failed: $e');
    }
  }

  static int _idCounter = 0;

  /// Returns a monotonic notification id that cannot replace a live heads-up.
  static int nextNotificationId() {
    if (_idCounter == 0) {
      _idCounter = DateTime.now().millisecondsSinceEpoch % 100000000;
    }
    return ++_idCounter;
  }

  /// Routes a plugin [response] payload to [onTap], buffering it when needed.
  static void routeResponse(NotificationResponse response) {
    final data = NotificationHeadsUp.decodePayload(response.payload, action: response.actionId);
    if (data == null) return;
    final handler = onTap;
    if (handler == null) {
      _pendingTap = data;
      return;
    }
    handler(data);
  }

  /// Initializes local notifications and replays a cold-start notification tap.
  Future<void> initialize() async {
    if (_initialized) return;
    const androidSettings = AndroidInitializationSettings('@drawable/ic_notification');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(android: androidSettings, iOS: iosSettings);
    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
      onDidReceiveBackgroundNotificationResponse: handleBackgroundNotificationResponse,
    );
    await _createChannels();
    await routeLaunchNotification();
    _initialized = true;
  }

  /// Routes the tap that launched a terminated app back through [onTap].
  Future<void> routeLaunchNotification() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    final response = details?.notificationResponse;
    if (details?.didNotificationLaunchApp != true || response == null) return;
    routeResponse(response);
  }

  void _onNotificationTap(NotificationResponse response) {
    routeResponse(response);
  }

  Future<void> _createChannels() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    for (final channel in NotificationChannels.android) {
      await android.createNotificationChannel(channel);
    }
  }

  /// Displays [title]/[body] as a max-importance heads-up on [channelId].
  Future<void> showHeadsUp({
    required int id,
    required String title,
    required String body,
    String channelId = NotificationChannels.general,
    String? payload,
    List<AndroidNotificationAction> actions = const [],
    void Function(String reason)? onBlocked,
  }) async {
    if (!await hasPermission()) {
      debugPrint('[NOTIF] heads-up dropped, POST_NOTIFICATIONS not granted');
      onBlocked?.call('notifications_disabled');
      return;
    }

    final androidDetails = AndroidNotificationDetails(
      channelId,
      NotificationChannels.nameFor(channelId),
      channelDescription: NotificationChannels.descriptionFor(channelId),
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      sound: NotificationChannels.sound,
      enableVibration: true,
      visibility: NotificationVisibility.public,
      showWhen: true,
      enableLights: true,
      ledColor: const Color(0xFF2196F3),
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

  /// Clears transient state between unit tests.
  @visibleForTesting
  static void resetForTesting() {
    _initialized = false;
    _granted = null;
    onTap = null;
    _pendingTap = null;
  }
}

/// Entry point used by the plugin's isolated background tap callback.
@pragma('vm:entry-point')
void handleBackgroundNotificationResponse(NotificationResponse response) {
  LocalNotificationService.routeResponse(response);
}
