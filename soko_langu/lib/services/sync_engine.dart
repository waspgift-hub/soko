import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/sync_operation.dart';
import 'network_state_service.dart';
import 'sync_queue_service.dart';

/// Executes one queued mutation against the remote API.
///
/// Handlers own conflict policy: for money, orders and payouts the server
/// always wins — the handler must reconcile local state from the response
/// instead of pushing local values. Throw on retryable failure; return
/// normally once the server has accepted (or authoritatively rejected)
/// the op so it is never sent twice.
typedef SyncHandler = Future<void> Function(SyncOperation op);

/// Central sync orchestrator (offline-first §20).
///
/// Wakes on [NetworkStateService.online], drains the outbox sequentially
/// (one at a time — preserves per-entity order and never fires hundreds
/// of requests at once), and backs off between failed drains. UI reads
/// [isSyncing] / [pendingCount] for the sync indicator states.
class SyncEngine extends ChangeNotifier {
  SyncEngine({
    required SyncQueueService queue,
    required NetworkStateService networkState,
    Map<SyncOperationType, SyncHandler>? handlers,
    this.maxRetries = 5,
  })  : _queue = queue,
        _networkState = networkState,
        _handlers = handlers ?? {};

  final SyncQueueService _queue;
  final NetworkStateService _networkState;
  final Map<SyncOperationType, SyncHandler> _handlers;
  final int maxRetries;

  VoidCallback? _networkListener;
  bool _draining = false;
  bool _started = false;
  int _consecutiveDrainFailures = 0;
  DateTime? _lastSyncedAt;
  String? _lastError;

  bool get isSyncing => _draining;
  int get pendingCount => _queue.pendingCount;
  int get failedCount => _queue.failedCount;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  String? get lastError => _lastError;

  /// Register (or replace) the handler for an operation type. Lets features
  /// plug in without the engine importing every service (no cycles).
  void registerHandler(SyncOperationType type, SyncHandler handler) {
    _handlers[type] = handler;
  }

  void start() {
    if (_started) return;
    _started = true;
    _networkListener = () {
      if (_networkState.isOnline) drain();
    };
    _networkState.addListener(_networkListener!);
    if (_networkState.isOnline) drain();
  }

  /// Drain the outbox now. No-op while a drain runs or when strictly
  /// offline; degraded waits for the next probe so retries aren't burned
  /// against a server the health check already knows is down.
  Future<void> drain() async {
    if (_draining || !_started) return;
    if (!_networkState.isOnline) return;
    _draining = true;
    notifyListeners();
    try {
      var progressed = false;
      while (true) {
        final batch = _queue.pending(limit: 20);
        if (batch.isEmpty) break;
        var batchFailed = false;
        for (final op in batch) {
          if (!_networkState.isOnline) {
            batchFailed = true;
            break;
          }
          final handler = _handlers[op.operationType];
          if (handler == null) {
            // No feature owns this op yet — leave it queued, not failed.
            continue;
          }
          await _queue.markProcessing(op);
          try {
            await handler(op).timeout(const Duration(seconds: 30));
            await _queue.markSynced(op);
            progressed = true;
          } catch (e) {
            batchFailed = true;
            if (op.retryCount + 1 >= maxRetries) {
              await _queue.markFailed(op, e);
              _lastError = e.toString();
            } else {
              op.status = SyncStatus.queued;
              op.retryCount += 1;
              op.updatedAt = DateTime.now();
              op.lastError = e.toString();
              await op.save();
            }
          }
        }
        if (batchFailed) break;
      }
      if (progressed) {
        _consecutiveDrainFailures = 0;
        _lastSyncedAt = DateTime.now();
        _lastError = null;
      }
    } finally {
      _draining = false;
      notifyListeners();
      _scheduleRetryDrain();
    }
  }

  // One delayed re-drain with exponential backoff when work remains;
  // the network listener also re-triggers on every offline→online flip.
  void _scheduleRetryDrain() {
    if (_queue.pendingCount == 0) return;
    _consecutiveDrainFailures++;
    final seconds = min(5 * pow(2, _consecutiveDrainFailures).toInt(), 300);
    Timer(Duration(seconds: seconds), () {
      if (_networkState.isOnline) drain();
    });
  }

  @override
  void dispose() {
    if (_networkListener != null) {
      _networkState.removeListener(_networkListener!);
      _networkListener = null;
    }
    super.dispose();
  }
}
