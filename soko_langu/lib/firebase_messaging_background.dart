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

  await AwesomeNotifications().initialize(
    null,
    NotificationService.channels,
  );

  // Prevent double notifications:
  // If the FCM message has a 'notification' payload (title/body at top level),
  // Firebase system service will auto-display it. Only create a manual local
  // notification for data-only messages to avoid duplicates.
  if (message.notification != null) {
    debugPrint('FCM background: display notification — letting system handle it');
    return;
  }

  // Data-only message — manually display via Awesome Notifications
  await FcmNotificationDisplay.show(
    message,
    notificationId: message.messageId.hashCode.abs().clamp(1, 2147483647),
    displayOnForeground: false,
  );
}
