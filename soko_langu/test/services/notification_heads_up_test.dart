import 'dart:convert';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/services/notification_channels.dart';
import 'package:soko_vibe/services/notification_heads_up.dart';

void main() {
  group('NotificationChannels', () {
    test('all heads-up channels are max importance with the custom sound', () {
      final channels = NotificationChannels.android;

      expect(channels.map((channel) => channel.id).toList(), [
        NotificationChannels.general,
        NotificationChannels.payments,
        NotificationChannels.chat,
        NotificationChannels.system,
        NotificationChannels.ride,
      ]);
      for (final channel in channels) {
        expect(channel.importance, Importance.max, reason: channel.id);
        expect(channel.playSound, isTrue, reason: channel.id);
        expect(channel.sound?.sound, 'soko_notification', reason: channel.id);
        expect(channel.enableVibration, isTrue, reason: channel.id);
      }
    });

    test('Dart channel IDs exist in the native Android channel creator', () {
      final native = File(
        'android/app/src/main/kotlin/com/sokolangu/app/MainActivity.kt',
      ).readAsStringSync();
      final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

      for (final channel in NotificationChannels.android) {
        expect(native, contains('"${channel.id}"'), reason: channel.id);
      }
      expect(native, contains('R.raw.soko_notification'));
      expect(manifest, contains(NotificationChannels.general));
    });

    test('notification types map to the expected channel', () {
      expect(NotificationChannels.forType('chat'), NotificationChannels.chat);
      expect(NotificationChannels.forType('group_chat'), NotificationChannels.chat);
      expect(NotificationChannels.forType('payment'), NotificationChannels.payments);
      expect(NotificationChannels.forType('order'), NotificationChannels.payments);
      expect(NotificationChannels.forType('dispatched'), NotificationChannels.payments);
      expect(NotificationChannels.forType('kyc'), NotificationChannels.payments);
      expect(NotificationChannels.forType('alert'), NotificationChannels.system);
      expect(NotificationChannels.forType('ride_request'), NotificationChannels.ride);
      expect(NotificationChannels.forType('flash_sale'), NotificationChannels.general);
      expect(NotificationChannels.forType(null), NotificationChannels.general);
    });
  });

  group('NotificationHeadsUp', () {
    test('chat uses the sender name and exposes a reply action', () {
      final headsUp = NotificationHeadsUp.fromPush(
        title: 'New message',
        body: 'Habari',
        type: 'chat',
        data: {'senderId': 'u1', 'senderName': 'Ashley'},
      );

      expect(headsUp.channelId, NotificationChannels.chat);
      expect(headsUp.title, 'Ashley');
      expect(headsUp.actions.map((action) => action.id), ['reply']);
      expect(jsonDecode(headsUp.payload)['type'], 'chat');
    });

    test('payment with an order exposes the pay action', () {
      final headsUp = NotificationHeadsUp.fromPush(
        title: 'Payment received',
        body: 'Paid',
        type: 'payment',
        data: {'orderId': 'ord-1'},
      );

      expect(headsUp.channelId, NotificationChannels.payments);
      expect(headsUp.actions.map((action) => action.id), ['pay']);
      expect(jsonDecode(headsUp.payload)['orderId'], 'ord-1');
    });

    test('seller quote marker without an order id has no pay action', () {
      final headsUp = NotificationHeadsUp.fromPush(
        title: 'New order',
        body: 'Set shipping',
        type: 'order',
        data: {'sellerId': 'seller-1', 'buyerId': 'buyer-1'},
      );

      expect(headsUp.actions, isEmpty);
    });

    test('shipping quote order with an id exposes the pay action', () {
      final headsUp = NotificationHeadsUp.fromPush(
        title: 'New order',
        body: 'Set shipping',
        type: 'order',
        data: {'orderId': 'ord-2', 'sellerId': 'seller-1', 'buyerId': 'buyer-1'},
      );

      expect(headsUp.actions.map((action) => action.id), ['pay']);
    });

    test('dispatched notification exposes the confirm action', () {
      final headsUp = NotificationHeadsUp.fromPush(
        title: 'Shipped',
        body: 'On the way',
        type: 'dispatched',
        data: {'orderId': 'ord-3'},
      );

      expect(headsUp.actions.map((action) => action.id), ['confirm']);
    });

    test('notification without an order has no action', () {
      final headsUp = NotificationHeadsUp.fromPush(
        title: 'Shipped',
        body: 'On the way',
        type: 'dispatched',
        data: {},
      );

      expect(headsUp.actions, isEmpty);
    });

    test('payload type is authoritative over data type', () {
      final headsUp = NotificationHeadsUp.fromPush(
        title: 'Alert',
        body: 'Body',
        type: 'system',
        data: {'type': 'stale', 'orderId': 'ord-4'},
      );

      expect(jsonDecode(headsUp.payload)['type'], 'system');
    });

    test('decodePayload adds action and rejects malformed payloads', () {
      final decoded = NotificationHeadsUp.decodePayload(
        jsonEncode({'type': 'payment', 'orderId': 'ord-5'}),
        action: 'pay',
      );

      expect(decoded?['action'], 'pay');
      expect(decoded?['orderId'], 'ord-5');
      expect(NotificationHeadsUp.decodePayload('not-json'), isNull);
      expect(NotificationHeadsUp.decodePayload(null), isNull);
    });
  });

  group('HeadsUpDeduplicator', () {
    test('suppresses the same key inside the window only', () {
      final deduplicator = HeadsUpDeduplicator(window: const Duration(seconds: 5));
      final start = DateTime(2026, 1, 1, 10);

      expect(deduplicator.shouldShow('key', start), isTrue);
      expect(deduplicator.shouldShow('key', start.add(const Duration(seconds: 2))), isFalse);
      expect(deduplicator.shouldShow('key', start.add(const Duration(seconds: 6))), isTrue);
      expect(deduplicator.shouldShow('other', start), isTrue);
    });
  });
}
