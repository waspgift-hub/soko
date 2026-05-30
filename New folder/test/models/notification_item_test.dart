import 'package:flutter_test/flutter_test.dart';
import 'package:soko_langu/models/notification_item.dart';

void main() {
  group('NotificationItem', () {
    test('constructor sets required fields', () {
      final now = DateTime.now();
      final n = NotificationItem(
        id: 'n1', type: 'chat', title: 'New message',
        body: 'Hello!', timestamp: now,
      );
      expect(n.id, 'n1');
      expect(n.type, 'chat');
      expect(n.title, 'New message');
      expect(n.body, 'Hello!');
      expect(n.timestamp, now);
    });

    test('defaults isRead to false and unreadCount to 0', () {
      final n = NotificationItem(
        id: 'n1', type: 'product', title: 'T', body: 'B',
        timestamp: DateTime.now(),
      );
      expect(n.isRead, false);
      expect(n.unreadCount, 0);
    });

    test('sets optional fields', () {
      final n = NotificationItem(
        id: 'n1', type: 'chat', title: 'T', body: 'B',
        timestamp: DateTime.now(),
        otherUserId: 'u1', otherUserName: 'John',
        otherUserImage: 'img.jpg', productId: 'p1',
        productImage: 'pimg.jpg', isRead: true, unreadCount: 3,
      );
      expect(n.otherUserId, 'u1');
      expect(n.otherUserName, 'John');
      expect(n.otherUserImage, 'img.jpg');
      expect(n.productId, 'p1');
      expect(n.productImage, 'pimg.jpg');
      expect(n.isRead, true);
      expect(n.unreadCount, 3);
    });
  });
}
