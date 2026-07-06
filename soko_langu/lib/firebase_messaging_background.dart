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

  await FcmNotificationDisplay.show(
    message,
    notificationId: message.messageId.hashCode.abs().clamp(1, 2147483647),
    displayOnForeground: false,
  );
}
