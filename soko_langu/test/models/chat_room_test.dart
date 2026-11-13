import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/models/chat_room.dart';
import 'package:soko_vibe/models/message_model.dart';

void main() {
  group('ChatRoom.fromMap', () {
    test('parses a well-formed room', () {
      final when = DateTime.utc(2026, 1, 2, 3, 4, 5);
      final room = ChatRoom.fromMap('r1', {
        'participants': ['a', 'b'],
        'last_message': 'hi',
        'last_timestamp': Timestamp.fromDate(when),
        'unread_counts': {'a': 0, 'b': 2},
        'product_id': 'p1',
      });

      expect(room.participants, ['a', 'b']);
      expect(room.lastMessage, 'hi');
      expect(room.lastTimestamp?.millisecondsSinceEpoch,
          when.millisecondsSinceEpoch);
      expect(room.unreadCountFor('b'), 2);
      expect(room.productId, 'p1');
    });

    test('tolerates legacy rooms with wrong field types', () {
      final room = ChatRoom.fromMap('r2', {
        'participants': 'not-a-list',
        'last_message': 42,
        'last_timestamp': 'yesterday',
        'unread_count_buyer': 'many',
        'pinned_by': [1, 'a'],
      });

      expect(room.participants, isEmpty);
      expect(room.lastMessage, '');
      expect(room.lastTimestamp, isNull);
      expect(room.unreadCountBuyer, 0);
      expect(room.pinnedBy, ['a']);
    });
  });

  group('Message.fromMap', () {
    test('tolerates malformed fields', () {
      final msg = Message.fromMap('m1', {
        'sender_id': 123,
        'timestamp': 'not-a-timestamp',
        'is_read': 'yes',
        'reactions': {
          '❤️': ['a', 2],
        },
      });

      expect(msg.senderId, '123');
      expect(msg.isRead, false);
      expect(msg.reactions['❤️'], ['a']);
    });
  });
}
