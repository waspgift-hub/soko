import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:soko_vibe/models/sync_operation.dart';
import 'package:soko_vibe/services/sync_queue_service.dart';

void main() {
  late SyncQueueService queue;

  setUp(() async {
    final dir = await Directory.systemTemp.createTemp('sync_queue_test');
    Hive.init(dir.path);
    queue = await SyncQueueService.init();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
  });

  test('adapter round-trips every field', () async {
    final op = await queue.enqueue(
      operationType: SyncOperationType.wishlistAdd,
      entityType: 'product',
      entityId: 'p1',
      payload: {'a': 1},
      priority: SyncPriority.high,
      idempotencyKey: 'k1',
    );
    final fetched = queue.pending().single;
    expect(fetched.id, op.id);
    expect(fetched.operationType, SyncOperationType.wishlistAdd);
    expect(fetched.payload, {'a': 1});
    expect(fetched.priority, SyncPriority.high);
    expect(fetched.idempotencyKey, 'k1');
    expect(fetched.status, SyncStatus.queued);
  });

  test('same idempotency key never queues twice', () async {
    final first = await queue.enqueue(
      operationType: SyncOperationType.followStore,
      entityType: 'store',
      entityId: 's1',
      idempotencyKey: 'same-key',
    );
    final second = await queue.enqueue(
      operationType: SyncOperationType.followStore,
      entityType: 'store',
      entityId: 's1',
      idempotencyKey: 'same-key',
    );
    expect(second.id, first.id);
    expect(queue.pendingCount, 1);
  });

  test('pending drains high priority before medium', () async {
    await queue.enqueue(
      operationType: SyncOperationType.profileUpdate,
      entityType: 'user',
      entityId: 'u1',
      priority: SyncPriority.medium,
    );
    await queue.enqueue(
      operationType: SyncOperationType.chatSend,
      entityType: 'message',
      entityId: 'm1',
      priority: SyncPriority.high,
    );
    final pending = queue.pending();
    expect(pending.first.entityId, 'm1');
  });

  test('failed ops keep retry count and can requeue', () async {
    final op = await queue.enqueue(
      operationType: SyncOperationType.chatSend,
      entityType: 'message',
      entityId: 'm1',
      priority: SyncPriority.high,
    );
    await queue.markFailed(op, Exception('no route'));
    expect(op.retryCount, 1);
    expect(op.status, SyncStatus.failed);
    expect(queue.pendingCount, 0);
    expect(queue.failedCount, 1);
    await queue.requeue(op);
    expect(queue.pendingCount, 1);
  });

  test('queued ops survive box close + reopen', () async {
    await queue.enqueue(
      operationType: SyncOperationType.wishlistRemove,
      entityType: 'product',
      entityId: 'p9',
    );
    await Hive.box<SyncOperation>('sync_outbox').close();
    final reopened = await SyncQueueService.init();
    expect(reopened.pendingCount, 1);
    expect(reopened.pending().single.entityId, 'p9');
  });
}
