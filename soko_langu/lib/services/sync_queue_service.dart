import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/sync_operation.dart';

/// Persistent mutation outbox (offline-first §21).
///
/// Hive-backed so queued work survives app/device restart. The engine
/// drains it; features only ever call [enqueue]. Not a ChangeNotifier —
/// the engine owns UI-visible sync state.
class SyncQueueService {
  SyncQueueService._(this._box);

  final Box<SyncOperation> _box;

  static const String _boxName = 'sync_outbox';

  /// Retention + backpressure caps keep the box from growing unboundedly
  /// on devices that stay offline for weeks (storage respect, §9/§34).
  static const int maxQueued = 500;
  static const Duration syncedRetention = Duration(days: 2);

  static Future<SyncQueueService> init() async {
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(SyncOperationAdapter());
    }
    final box = await Hive.openBox<SyncOperation>(_boxName);
    final service = SyncQueueService._(box);
    await service._evictExpiredSynced();
    return service;
  }

  /// Queue a mutation. Returns the existing entry when the same
  /// [idempotencyKey] is already queued — UI double-taps never duplicate.
  Future<SyncOperation> enqueue({
    required SyncOperationType operationType,
    required String entityType,
    required String entityId,
    Map<String, dynamic>? payload,
    SyncPriority priority = SyncPriority.medium,
    String? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? const Uuid().v4();
    for (final op in _box.values) {
      if (op.idempotencyKey == key && op.status != SyncStatus.synced) {
        return op;
      }
    }
    await _enforceCap(priority);
    final op = SyncOperation(
      id: const Uuid().v4(),
      operationType: operationType,
      entityType: entityType,
      entityId: entityId,
      payload: payload,
      idempotencyKey: key,
      priority: priority,
    );
    await _box.put(op.id, op);
    return op;
  }

  /// Oldest-first within priority order. Processing ops left behind by a
  /// crash are reclaimed as queued so no mutation is lost silently.
  List<SyncOperation> pending({int limit = 50}) {
    final items = _box.values.where((op) {
      if (op.status == SyncStatus.queued) return true;
      if (op.status == SyncStatus.processing) {
        op.status = SyncStatus.queued;
        op.updatedAt = DateTime.now();
        op.save().ignore();
        return true;
      }
      return false;
    }).toList()
      ..sort((a, b) {
        final pri = a.priority.index.compareTo(b.priority.index);
        if (pri != 0) return pri;
        return a.createdAt.compareTo(b.createdAt);
      });
    return items.take(limit).toList();
  }

  int get pendingCount => _box.values
      .where((op) =>
          op.status == SyncStatus.queued ||
          op.status == SyncStatus.processing)
      .length;

  int get failedCount =>
      _box.values.where((op) => op.status == SyncStatus.failed).length;

  Future<void> markProcessing(SyncOperation op) async {
    op.status = SyncStatus.processing;
    op.updatedAt = DateTime.now();
    await op.save();
  }

  Future<void> markSynced(SyncOperation op) async {
    op.status = SyncStatus.synced;
    op.updatedAt = DateTime.now();
    op.lastError = null;
    await op.save();
  }

  Future<void> markFailed(SyncOperation op, Object error) async {
    op.status = SyncStatus.failed;
    op.retryCount += 1;
    op.updatedAt = DateTime.now();
    op.lastError = error.toString();
    await op.save();
  }

  /// Requeue a dead-lettered op for manual retry from the UI.
  Future<void> requeue(SyncOperation op) async {
    op.status = SyncStatus.queued;
    op.updatedAt = DateTime.now();
    await op.save();
  }

  Future<void> cancel(String id) async {
    final op = _box.get(id);
    if (op == null) return;
    op.status = SyncStatus.cancelled;
    op.updatedAt = DateTime.now();
    await op.save();
  }

  Future<void> _evictExpiredSynced() async {
    final cutoff = DateTime.now().subtract(syncedRetention);
    for (final op in _box.values.toList()) {
      if (op.status == SyncStatus.synced && op.updatedAt.isBefore(cutoff)) {
        await op.delete();
      }
    }
  }

  // Backpressure: synced rows go first, then the oldest low-priority
  // queued rows. High-priority (chat/account) rows are never evicted —
  // losing a message is worse than using storage.
  Future<void> _enforceCap(SyncPriority incoming) async {
    if (pendingCount < maxQueued) return;
    for (final op in _box.values.toList()) {
      if (pendingCount < maxQueued) return;
      if (op.status == SyncStatus.synced) await op.delete();
    }
    if (incoming == SyncPriority.high) return;
    final evictable = _box.values
        .where((op) =>
            op.status == SyncStatus.queued &&
            op.priority == SyncPriority.low)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final op in evictable) {
      if (pendingCount < maxQueued) return;
      await op.delete();
    }
  }
}
