import 'package:hive/hive.dart';

/// What the queued mutation does. String-backed so reordering never
/// corrupts the persisted outbox.
enum SyncOperationType {
  wishlistAdd,
  wishlistRemove,
  followStore,
  unfollowStore,
  followUser,
  unfollowUser,
  chatSend,
  profileUpdate,
}

/// Lifecycle of a queued mutation (§21).
enum SyncStatus { queued, processing, synced, failed, cancelled }

/// Drain order: chat + account ops first, analytics-grade data last.
enum SyncPriority { high, medium, low }

/// One persisted outbox entry. Survives app/device restart via Hive.
class SyncOperation extends HiveObject {
  final String id;
  final SyncOperationType operationType;
  final String entityType;
  final String entityId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  DateTime updatedAt;
  int retryCount;
  SyncStatus status;
  final String idempotencyKey;
  final SyncPriority priority;
  String? lastError;

  SyncOperation({
    required this.id,
    required this.operationType,
    required this.entityType,
    required this.entityId,
    Map<String, dynamic>? payload,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.retryCount = 0,
    this.status = SyncStatus.queued,
    required this.idempotencyKey,
    this.priority = SyncPriority.medium,
    this.lastError,
  })  : payload = payload ?? const {},
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();
}

/// Manual TypeAdapter — no code generation needed.
class SyncOperationAdapter extends TypeAdapter<SyncOperation> {
  @override
  final int typeId = 3;

  @override
  SyncOperation read(BinaryReader reader) {
    final fields = reader.readMap().cast<int, dynamic>();
    return SyncOperation(
      id: fields[0] as String,
      operationType: SyncOperationType.values[fields[1] as int],
      entityType: fields[2] as String,
      entityId: fields[3] as String,
      payload: (fields[4] as Map?)?.cast<String, dynamic>() ?? const {},
      createdAt: fields[5] as DateTime,
      updatedAt: fields[6] as DateTime,
      retryCount: fields[7] as int? ?? 0,
      status: SyncStatus.values[fields[8] as int],
      idempotencyKey: fields[9] as String,
      priority: SyncPriority.values[fields[10] as int? ?? 1],
      lastError: fields[11] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, SyncOperation obj) {
    writer.writeMap({
      0: obj.id,
      1: obj.operationType.index,
      2: obj.entityType,
      3: obj.entityId,
      4: obj.payload,
      5: obj.createdAt,
      6: obj.updatedAt,
      7: obj.retryCount,
      8: obj.status.index,
      9: obj.idempotencyKey,
      10: obj.priority.index,
      11: obj.lastError,
    });
  }
}
