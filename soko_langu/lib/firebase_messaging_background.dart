import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';
import 'services/fcm_notification_display.dart';

/// Top-level background FCM handler — must be registered in main() before runApp.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Skip duplicate: if the server sent a notification payload, the system
  // already displayed it natively. Only show via Awesome Notifications for
  // data-only payloads (e.g. chat) to avoid double notifications.
  if (message.notification != null) {
    debugPrint('[FCM BG] notification payload present — skipping Awesome duplicate (type=${message.data['type']})');
    return;
  }

  await AwesomeNotifications().initialize(
    'resource://drawable/ic_notification',
    NotificationService.channels,
  );

  await FcmNotificationDisplay.show(
    message,
    notificationId: message.messageId.hashCode.abs().clamp(1, 2147483647),
    displayOnForeground: false,
  );
}
