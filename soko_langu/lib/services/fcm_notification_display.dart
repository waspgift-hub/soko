import 'dart:typed_data';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'notification_service.dart';

/// Shared FCM → Awesome Notifications display for foreground and background.
class FcmNotificationDisplay {
  /// Stable notification ID derived from message data for update support.
  static int _stableId(Map<String, dynamic> data) {
    final msgId = data['messageId'] ?? data['notificationId'] ?? '';
    return msgId.hashCode.abs().clamp(1, 2147483647);
  }

  static Future<void> show(
    RemoteMessage message, {
    int? notificationId,
    bool displayOnForeground = true,
  }) async {
    final data = message.data;
    final title =
        message.notification?.title ?? data['title'] as String? ?? '';
    final body =
        message.notification?.body ?? data['body'] as String? ?? '';
    if (title.isEmpty && body.isEmpty) return;

    final id = notificationId ?? _stableId(data);
    final type = data['type'] as String? ?? 'general';
    final isChat = type == 'chat' || type == 'group_chat';
    final isPayment = type == 'payment';
    final isBigPicture =
        ['flash_sale', 'boost', 'price_drop'].contains(type);
    final imageUrl = data['image'] as String?;
    final payload = data.map((k, v) => MapEntry(k, v?.toString()));
    final channelKey = isChat
        ? 'chat_messages_v3'
        : isPayment
            ? 'payments_notifications'
            : 'general_notifications_v3';

    // Group key for notification groups (Android 7.0+)
    final groupKey = isChat ? 'group_chat' : 'group_general';

    // Action buttons
    final actionButtons = <NotificationActionButton>[];
    if (isChat && data['senderId'] != null) {
      actionButtons.add(NotificationActionButton(
        key: 'REPLY',
        label: 'Reply',
        requireInputText: true,
        autoDismissible: true,
      ));
    }
    if (type == 'order') {
      actionButtons.add(NotificationActionButton(
        key: 'VIEW_ORDER',
        label: 'View Order',
        autoDismissible: true,
      ));
    }

    if (isBigPicture && imageUrl != null && imageUrl.isNotEmpty) {
      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: id,
          channelKey: 'general_notifications_v3',
          title: title,
          body: body,
          bigPicture: imageUrl,
          largeIcon: imageUrl,
          notificationLayout: NotificationLayout.BigPicture,
          displayOnForeground: displayOnForeground,
          displayOnBackground: true,
          payload: payload,
          customSound: NotificationService.customSound,
          groupKey: groupKey,
        ),
        actionButtons: actionButtons.isEmpty ? null : actionButtons,
      );
      return;
    }

    if (isChat) {
      final senderName =
          data['senderName'] as String? ?? 'New message';
      final senderAvatar = data['senderPhotoUrl'] as String? ??
          data['senderAvatar'] as String?;
      final conversationName = data['conversationName'] as String? ??
          data['chatName'] as String?;
      final isGroupChat = type == 'group_chat';

      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: id,
          channelKey: channelKey,
          title: senderName,
          body: body,
          summary: conversationName,
          largeIcon: senderAvatar,
          roundedLargeIcon: true,
          displayOnForeground: displayOnForeground,
          displayOnBackground: true,
          payload: payload,
          customSound: NotificationService.customSound,
          groupKey: groupKey,
          notificationLayout: isGroupChat
              ? NotificationLayout.MessagingGroup
              : NotificationLayout.Messaging,
        ),
        actionButtons: actionButtons.isEmpty ? null : actionButtons,
      );
      return;
    }

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: id,
        channelKey: channelKey,
        title: title,
        body: body,
        displayOnForeground: displayOnForeground,
        displayOnBackground: true,
        payload: payload,
        customSound: NotificationService.customSound,
        groupKey: groupKey,
        notificationLayout: body.length > 120
            ? NotificationLayout.BigText
            : NotificationLayout.Default,
      ),
      actionButtons: actionButtons.isEmpty ? null : actionButtons,
    );
  }
}

Int64List get fcmVibrationPattern =>
    Int64List.fromList([0, 200, 100, 200, 100, 300]);
