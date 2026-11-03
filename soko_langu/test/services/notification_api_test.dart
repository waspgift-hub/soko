import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

import 'package:soko_vibe/services/notification_api.dart';
import 'package:soko_vibe/utils/network_error.dart';

void main() {
  group('NotificationApiClient', () {
    http.Client makeClient(Map<String, dynamic> response, {int statusCode = 200}) {
      return http_testing.MockClient((request) async {
        return http.Response(
          jsonEncode(response),
          statusCode,
          headers: {'content-type': 'application/json'},
        );
      });
    }

    test('fetchNotifications returns list', () async {
      final client = makeClient({
        'success': true,
        'data': {
          'notifications': [
            {
              'id': 'n1',
              'type': 'order_update',
              'title': 'Order shipped',
              'body': 'Your order has been dispatched',
              'data': {'senderId': 'u1', 'senderName': 'Seller', 'productId': 'p1'},
              'isRead': false,
              'createdAt': '2026-01-15T10:00:00.000Z',
            },
            {
              'id': 'n2',
              'type': 'chat',
              'title': 'New message',
              'body': 'Hello!',
              'data': {},
              'isRead': true,
              'createdAt': '2026-01-14T09:00:00.000Z',
            },
          ],
          'pagination': {'page': 1, 'limit': 20, 'total': 2, 'totalPages': 1},
        },
      });

      final api = NotificationApiClient(
        httpClient: client,
        tokenProvider: () async => 'test-token',
      );

      final result = await api.fetchNotifications();

      expect(result.notifications.length, 2);
      expect(result.notifications[0].id, 'n1');
      expect(result.notifications[0].type, 'order_update');
      expect(result.notifications[0].isRead, false);
      expect(result.notifications[1].id, 'n2');
      expect(result.notifications[1].isRead, true);
    });

    test('fetchUnreadCount returns count', () async {
      final client = makeClient({
        'success': true,
        'data': {'count': 3},
      });

      final api = NotificationApiClient(
        httpClient: client,
        tokenProvider: () async => 'test-token',
      );

      final count = await api.fetchUnreadCount();
      expect(count, 3);
    });

    test('markRead returns true on 200', () async {
      final client = makeClient({
        'success': true,
        'data': {'marked': true},
      });

      final api = NotificationApiClient(
        httpClient: client,
        tokenProvider: () async => 'test-token',
      );

      final result = await api.markRead('notif-123');
      expect(result, true);
    });

    test('markAllRead returns count', () async {
      final client = makeClient({
        'success': true,
        'data': {'marked': 5},
      });

      final api = NotificationApiClient(
        httpClient: client,
        tokenProvider: () async => 'test-token',
      );

      final count = await api.markAllRead();
      expect(count, 5);
    });

    test('delete returns true on 200', () async {
      final client = makeClient({
        'success': true,
        'data': {'deleted': true},
      });

      final api = NotificationApiClient(
        httpClient: client,
        tokenProvider: () async => 'test-token',
      );

      final result = await api.delete('notif-123');
      expect(result, true);
    });

    test('deleteAll returns count', () async {
      final client = makeClient({
        'success': true,
        'data': {'deleted': 7},
      });

      final api = NotificationApiClient(
        httpClient: client,
        tokenProvider: () async => 'test-token',
      );

      final count = await api.deleteAll();
      expect(count, 7);
    });

    test('throws NetworkError when token is null', () async {
      final api = NotificationApiClient(
        httpClient: makeClient({'success': false}),
        tokenProvider: () async => null,
      );

      expect(
        () => api.fetchNotifications(),
        throwsA(isA<NetworkError>()),
      );
    });
  });
}
