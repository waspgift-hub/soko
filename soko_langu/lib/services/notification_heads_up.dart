import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_channels.dart';

/// A fully resolved local heads-up for an incoming push or Firestore fallback.
class NotificationHeadsUp {
  const NotificationHeadsUp._({
    required this.channelId,
    required this.title,
    required this.body,
    required this.type,
    required this.data,
    required this.actions,
  });

  /// Builds the heads-up presented for [type] and its [data] payload.
  factory NotificationHeadsUp.fromPush({
    required String title,
    required String body,
    required String type,
    required Map<String, dynamic> data,
  }) {
    final channelId = NotificationChannels.forType(type);
    final actions = <AndroidNotificationAction>[];
    String headsUpTitle = title;

    switch (type) {
      case 'chat':
      case 'group_chat':
        headsUpTitle = data['senderName'] as String? ?? title;
        actions.add(const AndroidNotificationAction('reply', 'Jibu', showsUserInterface: true));
        break;
      case 'payment':
      case 'order':
        final hasOrder = data['orderId'] != null || data['transactionId'] != null;
        final isPayableQuote = type == 'order' && data['sellerId'] != null;
        if (hasOrder && (type == 'payment' || isPayableQuote)) {
          actions.add(
            const AndroidNotificationAction('pay', 'Lipa Sasa', showsUserInterface: true),
          );
        }
        break;
      case 'dispatched':
      case 'delivery_confirmed':
        if (data['orderId'] != null || data['transactionId'] != null) {
          actions.add(
            const AndroidNotificationAction(
              'confirm',
              'Thibitisha Upokeaji',
              showsUserInterface: true,
            ),
          );
        }
        break;
    }

    return NotificationHeadsUp._(
      channelId: channelId,
      title: headsUpTitle,
      body: body,
      type: type,
      data: data,
      actions: List.unmodifiable(actions),
    );
  }

  final String channelId;
  final String title;
  final String body;
  final String type;
  final Map<String, dynamic> data;
  final List<AndroidNotificationAction> actions;

  /// Payload stored on the local notification so taps route like OneSignal taps.
  String get payload => jsonEncode(<String, dynamic>{...data, 'type': type});

  /// Stable key used to drop duplicate heads-ups from push and fallback paths.
  String get deduplicationKey => [
    channelId,
    data['notificationId'],
    data['orderId'],
    data['transactionId'],
    data['roomId'],
    data['payoutId'],
    title,
    body,
  ].map((value) => value?.toString() ?? '').join('|');

  /// Decodes a local notification payload and attaches the tapped [action].
  static Map<String, dynamic>? decodePayload(String? payload, {String? action}) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return null;
      final data = Map<String, dynamic>.from(decoded);
      if (action != null && action.isNotEmpty) data['action'] = action;
      return data;
    } catch (_) {
      return null;
    }
  }
}

/// Suppresses the same heads-up arriving twice from push and Firestore fallback.
class HeadsUpDeduplicator {
  HeadsUpDeduplicator({this.window = const Duration(seconds: 8)});

  final Duration window;
  final Map<String, DateTime> _seen = {};

  /// Returns whether [key] has not been shown inside the suppression window.
  bool shouldShow(String key, [DateTime? now]) {
    final current = now ?? DateTime.now();
    _seen.removeWhere((_, shownAt) => current.difference(shownAt) > window);
    if (_seen.containsKey(key)) return false;
    _seen[key] = current;
    return true;
  }
}
