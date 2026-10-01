import 'dart:convert';
import 'dart:ui' show Color;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class LocalNotificationService {
  static final LocalNotificationService _instance = LocalNotificationService._();
  factory LocalNotificationService() => _instance;
  LocalNotificationService._();

  // Static so the permission helpers can reach it without an instance: they are
// called from static context before/independently of any singleton usage.
// Instance methods below reference it unqualified, which still resolves here.
static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Whether the OS will actually display anything we post.
  ///
  /// On Android 13+ (API 33) a notification is not shown *at all* without
  /// POST_NOTIFICATIONS — not even in the tray — and `show()` returns normally,
  /// so without this flag a caller cannot tell "shown" from "silently dropped".
  /// OneSignal's permission covers the same OS permission, but push and local
  /// notifications are separate code paths: a user who declined push still gets
  /// the in-app→heads-up fallback, which needs this permission to be visible at
  /// all.
  static bool? _granted;

  /// Last known POST_NOTIFICATIONS state. Null until [hasPermission] or
  /// [requestPermission] has run at least once.
  static bool? get granted => _granted;

  /// Current POST_NOTIFICATIONS state without prompting.
  ///
  /// Cached after the first call: this is read on every notification we post,
  /// and on Android it is a cheap but non-free platform-channel round trip.
  static Future<bool> hasPermission() async {
    if (_granted != null) return _granted!;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true; // non-Android: nothing to gate
    try {
      _granted = await android.areNotificationsEnabled() ?? false;
    } catch (_) {
      _granted = null;
    }
    return _granted ?? false;
  }

  /// Asks for POST_NOTIFICATIONS on Android 13+.
  ///
  /// No-op below Android 13 (the permission is implicit) and on iOS, where the
  /// equivalent prompts happen through the Darwin settings at init. Returns
  /// whether notifications may be posted.
  ///
  /// Safe to call more than once: Android collapses a second prompt into a
  /// no-op, so the caller still has to handle `false` by sending the user to
  /// system settings rather than nagging.
  static Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    try {
      _granted = await android.requestNotificationsPermission() ?? false;
    } catch (_) {
      _granted = null;
    }
    debugPrint('[NOTIF] POST_NOTIFICATIONS granted=$_granted');
    return _granted ?? false;
  }

  /// Opens this app's notification settings in the OS.
///
/// Android does not re-prompt after a denial (and "don't ask again" cannot be
/// distinguished from a plain decline), so for a blocked user this deep link is
/// the only way back. Pair it with a check of [granted] rather than a second
/// prompt, which would silently do nothing.
static Future<void> openSystemSettings() async {
    try {
      await openAppSettings();
    } catch (e) {
      debugPrint('[NOTIF] openAppSettings failed: $e');
    }
  }

  /// Routes local heads-up taps to the same handlers OneSignal uses.
  static void Function(Map<String, dynamic> data)? onTap;

  static int _idCounter = 0;

  /// Returns a monotonic notification id seeded from the clock so IDs never
  /// collide within a session and rarely collide across restarts, unlike the
  /// old `millisecondsSinceEpoch % 2^31` scheme which could reuse an id for a
  /// still-active notification and silently replace it.
  static int nextNotificationId() {
    if (_idCounter == 0) {
      _idCounter = DateTime.now().millisecondsSinceEpoch % 100000000;
    }
    return ++_idCounter;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    const androidSettings = AndroidInitializationSettings('@drawable/ic_notification');
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
      'general_notifications_v6',
      'Soko Vibe',
      description: 'Flash sale, announcements, alerts',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
    ));
    await android.createNotificationChannel(const AndroidNotificationChannel(
      'payments_notifications_v6',
      'Payments',
      description: 'Malipo, escrow, payout, refund, KYC updates',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
    ));
    await android.createNotificationChannel(const AndroidNotificationChannel(
      'chat_messages_v6',
      'Chat Messages',
      description: 'New message notifications from chats',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
    ));
    await android.createNotificationChannel(const AndroidNotificationChannel(
      'system_alerts_v6',
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
    String channelId = 'general_notifications_v6',
    String? payload,
    List<AndroidNotificationAction> actions = const [],
    /// When false the notification was dropped because the OS forbids it.
    /// Callers that can offer the user a fix (a settings prompt) should use
    /// this to explain why nothing appeared, instead of silently failing.
    bool Function(String reason)? onBlocked,
  }) async {
    // Checked up front: on Android 13+ `show()` succeeds and nothing appears,
    // which is indistinguishable from a bug at the call site.
    if (!await hasPermission()) {
      debugPrint('[NOTIF] heads-up dropped, POST_NOTIFICATIONS not granted');
      onBlocked?.call('notifications_disabled');
      return;
    }

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
