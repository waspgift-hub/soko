import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Android notification channels used by local heads-ups and OneSignal pushes.
///
/// Android channel settings are immutable after first creation, so these IDs and
/// the custom sound must stay in lockstep with `MainActivity.createNotificationChannels()`.
class NotificationChannels {
  const NotificationChannels._();

  static const general = 'general_notifications_v6';
  static const payments = 'payments_notifications_v6';
  static const chat = 'chat_messages_v6';
  static const system = 'system_alerts_v6';
  static const ride = 'ride_notifications_v6';

  static const soundResource = 'soko_notification';
  static const sound = RawResourceAndroidNotificationSound(soundResource);

  /// Channel definitions installed by the Flutter side at startup.
  static List<AndroidNotificationChannel> get android => [
    AndroidNotificationChannel(
      general,
      'Soko Vibe',
      description: 'Flash sale, announcements, alerts',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
      enableLights: true,
      showBadge: true,
      sound: sound,
    ),
    AndroidNotificationChannel(
      payments,
      'Payments',
      description: 'Malipo, escrow, payout, refund, KYC updates',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
      enableLights: true,
      showBadge: true,
      sound: sound,
    ),
    AndroidNotificationChannel(
      chat,
      'Chat Messages',
      description: 'New message notifications from chats',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
      enableLights: true,
      showBadge: true,
      sound: sound,
    ),
    AndroidNotificationChannel(
      system,
      'System Alerts',
      description: 'Account security, suspension, verification alerts',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
      enableLights: true,
      showBadge: true,
      sound: sound,
    ),
    AndroidNotificationChannel(
      ride,
      'Ride Updates',
      description: 'Ride requests, cancellations, trip updates',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
      enableLights: true,
      showBadge: true,
      sound: sound,
    ),
  ];

  /// Maps an incoming notification type to the channel that should display it.
  static String forType(String? type) {
    switch (type) {
      case 'chat':
      case 'group_chat':
        return chat;
      case 'system':
      case 'admin':
      case 'alert':
        return system;
      case 'ride':
      case 'ride_request':
      case 'trip_update':
        return ride;
      case 'payment':
      case 'payment_failed':
      case 'refund':
      case 'cancelled':
      case 'withdrawal':
      case 'auto_withdrawal':
      case 'escrow_release':
      case 'escrow_auto_release':
      case 'dispute':
      case 'dispute_resolved':
      case 'auto_payout':
      case 'payout':
      case 'order':
      case 'order_update':
      case 'dispatched':
      case 'delivery_confirmed':
      case 'kyc':
      case 'kyc_approved':
      case 'kyc_rejected':
      case 'kyc_revoked':
      case 'deposit':
      case 'deposit_failed':
        return payments;
      default:
        return general;
    }
  }

  /// Label shown by Android for [channelId] when a details object is created.
  static String nameFor(String channelId) {
    switch (channelId) {
      case payments:
        return 'Payments';
      case chat:
        return 'Chat Messages';
      case system:
        return 'System Alerts';
      case ride:
        return 'Ride Updates';
      default:
        return 'Soko Vibe';
    }
  }

  /// Description shown by Android for [channelId].
  static String descriptionFor(String channelId) {
    switch (channelId) {
      case payments:
        return 'Malipo, escrow, payout, refund, KYC updates';
      case chat:
        return 'New message notifications from chats';
      case system:
        return 'Account security, suspension, verification alerts';
      case ride:
        return 'Ride requests, cancellations, trip updates';
      default:
        return 'Flash sale, announcements, alerts';
    }
  }
}
