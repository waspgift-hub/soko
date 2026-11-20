import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/services/local_notification_service.dart';
import 'package:soko_vibe/services/notification_channels.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestDefaultBinaryMessenger messenger;
  final calls = <MethodCall>[];
  bool permissionGranted = true;
  Map<dynamic, dynamic>? launchDetails;

  const channel = MethodChannel('dexterous.com/flutter/local_notifications');

  setUpAll(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'initialize':
          return true;
        case 'areNotificationsEnabled':
        case 'requestNotificationsPermission':
          return permissionGranted;
        case 'getNotificationAppLaunchDetails':
          return launchDetails ?? {'notificationLaunchedApp': false};
        default:
          return null;
      }
    });
  });

  tearDownAll(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  setUp(() {
    LocalNotificationService.resetForTesting();
    calls.clear();
    permissionGranted = true;
    launchDetails = null;
  });

  test('initialize creates every heads-up channel with max importance', () async {
    await LocalNotificationService().initialize();

    final channelCalls = calls.where((call) => call.method == 'createNotificationChannel').toList();
    expect(channelCalls.length, 5);
    for (final call in channelCalls) {
      final args = call.arguments as Map<dynamic, dynamic>;
      expect(args['importance'], Importance.max.value);
      expect(args['playSound'], isTrue);
      expect(args['sound'], 'soko_notification');
    }
    expect(
      channelCalls.map((call) => (call.arguments as Map<dynamic, dynamic>)['id']).toList(),
      NotificationChannels.android.map((channel) => channel.id).toList(),
    );
  });

  test('showHeadsUp drops the alert when the OS denies notifications', () async {
    permissionGranted = false;
    String? blockedReason;

    await LocalNotificationService().showHeadsUp(
      id: 1,
      title: 'Title',
      body: 'Body',
      onBlocked: (reason) => blockedReason = reason,
    );

    expect(blockedReason, 'notifications_disabled');
    expect(calls.any((call) => call.method == 'show'), isFalse);

    permissionGranted = true;
    await LocalNotificationService().showHeadsUp(id: 2, title: 'Title', body: 'Body');

    expect(calls.any((call) => call.method == 'show'), isTrue);
    expect(
      calls.where((call) => call.method == 'areNotificationsEnabled').length,
      2,
      reason: 'permission must be rechecked after an OS settings change',
    );
  });

  test('showHeadsUp posts a max-priority payload with actions', () async {
    const action = AndroidNotificationAction('pay', 'Lipa Sasa');

    await LocalNotificationService().showHeadsUp(
      id: 42,
      title: 'Payment',
      body: 'Paid',
      channelId: NotificationChannels.payments,
      payload: jsonEncode({'type': 'payment'}),
      actions: const [action],
    );

    final show = calls.singleWhere((call) => call.method == 'show');
    final args = show.arguments as Map<dynamic, dynamic>;
    final details = args['platformSpecifics'] as Map<dynamic, dynamic>;
    expect(args['id'], 42);
    expect(args['payload'], jsonEncode({'type': 'payment'}));
    expect(details['channelId'], NotificationChannels.payments);
    expect(details['importance'], Importance.max.value);
    expect(details['priority'], Priority.max.value);
    expect(details['sound'], 'soko_notification');
    expect(details['actions'], isNotEmpty);
  });

  test('tap responses add action ids before routing', () {
    Map<String, dynamic>? tapped;
    LocalNotificationService.setTapHandler((data) => tapped = data);

    LocalNotificationService.routeResponse(
      NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotificationAction,
        id: 7,
        actionId: 'confirm',
        payload: jsonEncode({'type': 'delivery_confirmed', 'orderId': 'ord-1'}),
      ),
    );

    expect(tapped?['action'], 'confirm');
    expect(tapped?['orderId'], 'ord-1');
  });

  test('background callbacks buffer taps until a handler is installed', () {
    LocalNotificationService.setTapHandler(null);
    handleBackgroundNotificationResponse(
      NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        id: 8,
        payload: jsonEncode({'type': 'chat', 'roomId': 'room-1'}),
      ),
    );

    expect(LocalNotificationService.pendingTap?['roomId'], 'room-1');

    Map<String, dynamic>? tapped;
    LocalNotificationService.setTapHandler((data) => tapped = data);
    expect(tapped?['roomId'], 'room-1');
    expect(LocalNotificationService.pendingTap, isNull);
  });

  test('cold-start launch payload is routed after initialize', () async {
    launchDetails = {
      'notificationLaunchedApp': true,
      'notificationResponse': {
        'notificationId': 9,
        'notificationResponseType': NotificationResponseType.selectedNotification.index,
        'payload': jsonEncode({'type': 'order', 'orderId': 'ord-9'}),
      },
    };
    Map<String, dynamic>? tapped;
    LocalNotificationService.setTapHandler((data) => tapped = data);

    await LocalNotificationService().initialize();

    expect(tapped?['type'], 'order');
    expect(tapped?['orderId'], 'ord-9');
  });
}
