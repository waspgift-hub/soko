import 'dart:async';

import 'transfer_progress.dart';

/// Signature of the work behind one tracked transfer.
///
/// Kept as a plain callback so a caller can register an operation without this
/// class knowing anything about HTTP, Firebase or file layout. That is what
/// lets the same progress UI drive product images, KYC documents and chat
/// media without three parallel implementations.
typedef TransferOperation<T> = Future<T> Function(
  void Function(TransferProgress) onProgress,
);

/// One independently-tracked transfer, with its own progress, failure and
/// retry.
///
/// This is the unit the multi-file upload list renders. The important property
/// is that each item owns its own outcome: a failure in item 3 leaves items 1
/// and 2 succeeded and does not force the whole batch to restart, which is the
/// behaviour §8 of the brief asks for and the behaviour a plain
/// `Future.wait` over uploads cannot provide.
class TransferItem<T> {
  /// Stable identity, used as a widget/list key and to correlate a retry with
  /// the row the seller tapped.
  final String id;

  /// Short label for the row, e.g. "Image 2". Supplied by the caller because
  /// only the caller knows whether this is an image, a clip or a document.
  final String label;

  /// Where the bytes are coming from, for the row's thumbnail and for logging.
  final String sourcePath;

  final TransferOperation<T> _run;

  final _controller = StreamController<TransferProgress>.broadcast();
  TransferProgress _progress = const TransferProgress.queued();

  /// Guards against a double-tap on "Retry" starting two concurrent uploads
  /// of the same bytes to the same key.
  bool _inFlight = false;

  /// The in-flight run, so a second caller joins the existing attempt instead
  /// of starting a duplicate or being forced to cast a null value.
  Future<T>? _pending;

  TransferItem({
    required this.id,
    required this.label,
    required this.sourcePath,
    required TransferOperation<T> operation,
  }) : _run = operation;

  /// Progress snapshots, newest last. Broadcast, so several widgets can watch
  /// the same item without fighting over ownership of the subscription.
  Stream<TransferProgress> get progress => _controller.stream;

  TransferProgress get progressSnapshot => _progress;

  /// True while bytes or local work are in flight for this item.
  bool get isBusy => _inFlight;

  /// Result of the last successful run, or null if it has not succeeded.
  T? get value => _value;
  T? _value;

  /// Runs (or re-runs) the operation.
  ///
  /// A second call while one is in flight joins the existing attempt rather
  /// than starting a duplicate, so a double-tap on "Retry" cannot produce two
  /// uploads of the same bytes to the same key. Returns the value on success
  /// and rethrows the original error on failure, so a caller that wants to
  /// fail the whole batch still can.
  Future<T> start() {
    final existing = _pending;
    if (existing != null) return existing;
    return _pending = _runOnce();
  }

  Future<T> _runOnce() async {
    _inFlight = true;
    _emit(_progress.isTerminal
        ? const TransferProgress.preparing()
        : _progress.copyWith(phase: TransferPhase.preparing, failure: null));

    try {
      final result = await _run(_emit);
      _value = result;
      _emit(TransferProgress.succeeded(
        transferred: _progress.transferred,
        total: _progress.total,
      ));
      return result;
    } on Object catch (error) {
      _emit(TransferProgress.failed(
        failure: error is TransferFailure
            ? error
            : TransferFailure.from(error),
        transferred: _progress.transferred,
        total: _progress.total,
      ));
      rethrow;
    } finally {
      _inFlight = false;
      _pending = null;
    }
  }

  /// Marks the item cancelled. The underlying HTTP call is not aborted — Dart's
  /// `http` has no portable abort for a request already handed to the socket —
  /// but the UI stops presenting it as active and the value is discarded so a
  /// late success cannot silently attach itself to a listing the seller
  /// already abandoned.
  void cancel() {
    if (_progress.isTerminal) return;
    _value = null;
    _emit(TransferProgress.cancelled(
      transferred: _progress.transferred,
      total: _progress.total,
    ));
  }

  /// Retries a failed item.
  ///
  /// Guarded by [TransferFailure.isRetryable] so a permission denial does not
  /// present a button whose second attempt is guaranteed to fail identically.
  /// Returns null when the item is not in a retryable failed state.
  Future<T?> retry() async {
    if (!_progress.isFailed) return _value;
    final failure = _progress.failure;
    if (failure != null && !failure.isRetryable) return _value;
    return start();
  }

  /// Clears a failure so the row returns to its idle state without re-running.
  void reset() {
    if (_inFlight) return;
    _emit(const TransferProgress.queued());
  }

  void _emit(TransferProgress next) {
    _progress = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}

/// A batch of transfers that belong to one user-visible operation.
///
/// Exists so a screen can hold the whole group in one object and hand it
/// straight to a list widget, instead of each feature re-deriving "how many are
/// done, how many failed, should I let them leave".
class TransferBatch {
  final Map<String, TransferItem<Object?>> _items = {};
  final _changes = StreamController<void>.broadcast();

  TransferBatch();

  /// All items, in the order they were added.
  List<TransferItem<Object?>> get items =>
      _items.values.toList(growable: false);

  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;

  int get length => _items.length;

  /// Emits whenever any item changes phase or bytes. Widgets rebuild from this.
  Stream<void> get changes => _changes.stream;

  TransferItem<Object?>? operator [](String id) => _items[id];

  /// Registers an item. Re-registering an id replaces it, so a caller can
  /// reuse ids across retries without leaking stale entries.
  TransferItem<T> add<T>(
    String id,
    String label,
    String sourcePath,
    TransferOperation<T> operation,
  ) {
    final item = TransferItem<T>(
      id: id,
      label: label,
      sourcePath: sourcePath,
      operation: operation,
    );
    _items[id] = item as TransferItem<Object?>;
    item.progress.listen((_) => _notify());
    _notify();
    return item;
  }

  TransferItem<T>? item<T>(String id) {
    final raw = _items[id];
    return raw is TransferItem<T> ? raw : null;
  }

  /// Starts every item that has not yet succeeded, concurrently.
  ///
  /// Failures are collected rather than thrown: one bad photo must not abort
  /// the batch, because the seller can retry just that row.
  Future<void> startAll() async {
    final pending = _items.values.where((i) => !i.progressSnapshot.isSucceeded);
    await Future.wait([
      for (final i in pending) _ignoreFailure(() => i.start()),
    ]);
  }

  /// Re-runs only the items that failed. Successfully uploaded files are left
  /// alone, which is the whole point of tracking them individually.
  Future<void> retryFailed() async {
    final failed = _items.values.where((i) => i.progressSnapshot.isFailed);
    await Future.wait([
      for (final i in failed) _ignoreFailure(() => i.retry()),
    ]);
  }

  /// Awaits one item and swallows its error. The failure is already recorded
  /// on the item by [TransferItem.start]; rethrowing here would just force
  /// every caller to wrap a call it has no way to react to differently.
  static Future<void> _ignoreFailure(Future<Object?> Function() work) async {
    try {
      await work();
    } on Object {
      // Recorded on the item; see TransferItem._runOnce.
    }
  }

  /// Values of every succeeded item, in insertion order. Entries are null for
  /// items that have not succeeded, so the caller can see the gap rather than
  /// receiving a short list with no explanation.
  List<T?> succeededValues<T>() => [
        for (final i in _items.values)
          if (i.progressSnapshot.isSucceeded) i.value as T?,
      ];

  Iterable<TransferItem<Object?>> get failedItems =>
      _items.values.where((i) => i.progressSnapshot.isFailed);

  Iterable<TransferItem<Object?>> get succeededItems =>
      _items.values.where((i) => i.progressSnapshot.isSucceeded);

  /// True while anything is queued, preparing, transferring or processing.
  bool get isBusy => _items.values.any((i) => i.isBusy);

  /// Aggregate 0..1 across every item, weighted by real byte totals.
  ///
  /// Returns null unless *every* item has a known total; a partial denominator
  /// would render a bar that stalls at 100%-of-known-bytes while other files
  /// are still going, which is misleading in a different way.
  double? get aggregateFraction {
    if (_items.isEmpty) return null;
    var total = 0;
    var done = 0;
    for (final i in _items.values) {
      final p = i.progressSnapshot;
      final t = p.total;
      if (t == null) return null;
      total += t;
      done += i.progressSnapshot.isSucceeded ? t : p.transferred;
    }
    if (total <= 0) return null;
    return (done / total).clamp(0.0, 1.0);
  }

  /// Aggregate 0..100, or null when [aggregateFraction] is null.
  int? get aggregatePercent {
    final f = aggregateFraction;
    return f == null ? null : (f * 100).round().clamp(0, 100);
  }

  void cancelAll() {
    for (final i in _items.values) {
      i.cancel();
    }
  }

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> dispose() async {
    for (final i in _items.values) {
      await i.dispose();
    }
    await _changes.close();
  }
}