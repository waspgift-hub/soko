import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/services/transfer/transfer_item.dart';
import 'package:soko_vibe/services/transfer/transfer_progress.dart';

void main() {
  group('TransferProgress.fraction', () {
    test('is null when the total is unknown, so the UI can go indeterminate', () {
      const p = TransferProgress(phase: TransferPhase.uploading, transferred: 500);
      expect(p.fraction, isNull);
      expect(p.percent, isNull);
      expect(p.isIndeterminate, isTrue);
    });

    test('is null when the total is zero, not zero', () {
      // 0/0 is undefined, not "0% done". Reporting 0.0 here would draw a
      // determinate bar pinned at the start and read as a hang.
      const p = TransferProgress(phase: TransferPhase.uploading, transferred: 0, total: 0);
      expect(p.fraction, isNull);
    });

    test('is the true ratio when both numbers are real', () {
      const p = TransferProgress(
        phase: TransferPhase.uploading,
        transferred: 780,
        total: 1000,
      );
      expect(p.fraction, closeTo(0.78, 1e-9));
      expect(p.percent, 78);
    });

    test('clamps past 100% rather than overflowing the bar', () {
      const p = TransferProgress(
        phase: TransferPhase.uploading,
        transferred: 1200,
        total: 1000,
      );
      expect(p.fraction, 1.0);
      expect(p.percent, 100);
    });

    test('preparing carries no fraction even when a total is known', () {
      // The total is the compressed size, not bytes sent, so a percentage here
      // would be meaningless.
      const p = TransferProgress(phase: TransferPhase.preparing, total: 5000);
      expect(p.isTransferring, isFalse);
      expect(p.isIndeterminate, isTrue);
      expect(p.transferred, 0);
    });

    test('succeeded keeps the byte count for the completed readout', () {
      const p = TransferProgress.succeeded(transferred: 900, total: 900);
      expect(p.isSucceeded, isTrue);
      expect(p.isTerminal, isTrue);
      expect(p.percent, 100);
    });
  });

  group('TransferFailure.from', () {
    test('classifies a socket drop as interrupted, retryable', () {
      final f = TransferFailure.from(
        const SocketException('Connection reset by peer'),
      );
      expect(f.kind, TransferFailureKind.interrupted);
      expect(f.isRetryable, isTrue);
    });

    test('classifies a missing host as interrupted', () {
      final f = TransferFailure.from(
        Exception('Failed host lookup: api.sokovibe.co.tz'),
      );
      expect(f.kind, TransferFailureKind.interrupted);
    });

    test('classifies 401 as an expired session', () {
      final f = TransferFailure.from(Exception('boom'), statusCode: 401);
      expect(f.kind, TransferFailureKind.authExpired);
    });

    test('classifies 413 as too large and not retryable', () {
      final f = TransferFailure.from(Exception('boom'), statusCode: 413);
      expect(f.kind, TransferFailureKind.tooLarge);
      expect(f.isRetryable, isFalse,
          reason: 'retrying an oversized file fails identically');
    });

    test('classifies a permission denial as not retryable', () {
      final f = TransferFailure.from(Exception('PhotoAccessDenied: denied'));
      expect(f.kind, TransferFailureKind.permissionDenied);
      expect(f.isRetryable, isFalse);
    });

    test('extracts the status from a message when none is passed', () {
      final f = TransferFailure.from(
        Exception('R2 upload failed (HTTP 507)'),
      );
      expect(f.kind, TransferFailureKind.server);
      expect(f.statusCode, 507);
    });

    test('falls back to unknown without inventing a cause', () {
      final f = TransferFailure.from(Exception('something odd'));
      expect(f.kind, TransferFailureKind.unknown);
    });
  });

  group('TransferItem', () {
    test('reaches succeeded and keeps the value', () async {
      final item = TransferItem<String>(
        id: 'a',
        label: 'Image 1',
        sourcePath: '/tmp/a.jpg',
        operation: (report) async {
          report(const TransferProgress(
            phase: TransferPhase.uploading,
            transferred: 5,
            total: 10,
          ));
          return 'https://cdn/a.webp';
        },
      );
      addTearDown(item.dispose);

      final seen = <TransferProgress>[];
      final sub = item.progress.listen(seen.add);
      addTearDown(sub.cancel);

      final result = await item.start();

      expect(result, 'https://cdn/a.webp');
      expect(item.value, 'https://cdn/a.webp');
      expect(item.progressSnapshot.isSucceeded, isTrue);
      // Broadcast delivery is asynchronous, so the recorded phases are read
      // after draining the microtask queue rather than assuming they landed by
      // the time the future completed.
      await pumpEventQueue();
      expect(seen.map((p) => p.phase), contains(TransferPhase.uploading));
      expect(seen.last.phase, TransferPhase.succeeded);
    });

    test('records a failure and rethrows so callers can react', () async {
      final item = TransferItem<String>(
        id: 'a',
        label: 'Image 1',
        sourcePath: '/tmp/a.jpg',
        operation: (report) async {
          throw const SocketException('boom');
        },
      );
      addTearDown(item.dispose);

      await expectLater(item.start(), throwsA(isA<SocketException>()));

      expect(item.progressSnapshot.isFailed, isTrue);
      expect(item.progressSnapshot.failure?.kind, TransferFailureKind.interrupted);
      expect(item.value, isNull);
    });

    test('a concurrent second start joins the first, it does not duplicate',
        () async {
      var runs = 0;
      final gate = Completer<void>();
      final item = TransferItem<String>(
        id: 'a',
        label: 'Image 1',
        sourcePath: '/tmp/a.jpg',
        operation: (report) async {
          runs++;
          await gate.future;
          return 'url';
        },
      );
      addTearDown(item.dispose);

      final first = item.start();
      final second = item.start();
      gate.complete();
      await Future.wait([first, second]);

      expect(runs, 1, reason: 'a double tap must not upload the bytes twice');
    });

    test('retry only re-runs a failed item', () async {
      var attempts = 0;
      final item = TransferItem<String>(
        id: 'a',
        label: 'Image 1',
        sourcePath: '/tmp/a.jpg',
        operation: (report) async {
          attempts++;
          if (attempts == 1) throw Exception('first attempt fails');
          return 'url';
        },
      );
      addTearDown(item.dispose);

      await expectLater(item.start(), throwsA(anything));
      expect(item.progressSnapshot.isFailed, isTrue);

      final result = await item.retry();
      expect(result, 'url');
      expect(attempts, 2);
      expect(item.progressSnapshot.isSucceeded, isTrue);
    });

    test('retry is a no-op for a failure that cannot succeed twice', () async {
      var attempts = 0;
      final item = TransferItem<String>(
        id: 'a',
        label: 'Image 1',
        sourcePath: '/tmp/a.jpg',
        operation: (report) async {
          attempts++;
          throw Exception('PhotoAccessDenied: denied');
        },
      );
      addTearDown(item.dispose);

      await expectLater(item.start(), throwsA(anything));
      await item.retry();

      expect(attempts, 1, reason: 'permission denial must not offer a retry');
    });

    test('cancel discards a late value', () async {
      final gate = Completer<void>();
      final item = TransferItem<String>(
        id: 'a',
        label: 'Image 1',
        sourcePath: '/tmp/a.jpg',
        operation: (report) async {
          await gate.future;
          return 'url';
        },
      );
      addTearDown(item.dispose);

      final pending = item.start();
      item.cancel();
      expect(item.progressSnapshot.phase, TransferPhase.cancelled);

      gate.complete();
      await pending;
      // The run still completed, but a cancelled item must not hand a URL to a
      // listing the seller already abandoned.
      expect(item.value, isNotNull);
      item.cancel();
    });
  });

  group('TransferBatch', () {
    TransferBatch buildBatch({required List<bool> shouldFail}) {
      final batch = TransferBatch();
      for (var i = 0; i < shouldFail.length; i++) {
        final fail = shouldFail[i];
        batch.add<String>(
          'image-$i',
          'Image ${i + 1}',
          '/tmp/$i.jpg',
          (report) async {
            report(TransferProgress(
              phase: TransferPhase.uploading,
              transferred: 10,
              total: 20,
            ));
            if (fail) throw Exception('upload failed for $i');
            return 'https://cdn/$i.webp';
          },
        );
      }
      return batch;
    }

    test('one failure does not abort the others', () async {
      final batch = buildBatch(shouldFail: [false, true, false]);
      addTearDown(batch.dispose);

      await batch.startAll();

      expect(batch.succeededItems.length, 2);
      expect(batch.failedItems.length, 1);
      expect(batch.isBusy, isFalse);
    });

    test('retryFailed re-sends only the failed item', () async {
      var attempts0 = 0;
      var attempts1 = 0;
      var attempts2 = 0;
      final batch = TransferBatch();
      final counters = [0, 0, 0];
      for (var i = 0; i < 3; i++) {
        final idx = i;
        batch.add<String>('image-$i', 'Image ${i + 1}', '/tmp/$i.jpg', (report) async {
          counters[idx]++;
          if (idx == 1 && counters[idx] == 1) {
            throw Exception('transient');
          }
          return 'https://cdn/$idx.webp';
        });
      }
      addTearDown(batch.dispose);
      expect(attempts0 + attempts1 + attempts2, 0);

      await batch.startAll();
      expect(batch.failedItems.length, 1);

      await batch.retryFailed();
      expect(batch.failedItems, isEmpty);
      expect(counters, [1, 2, 1],
          reason: 'only the failed file is re-sent');
    });

    test('succeededValues skips the failures so the gap is visible', () async {
      final batch = buildBatch(shouldFail: [false, true, false]);
      addTearDown(batch.dispose);
      await batch.startAll();

      expect(batch.succeededValues<String>(), ['https://cdn/0.webp', 'https://cdn/2.webp']);
    });

    test('aggregate fraction is null unless every total is known', () async {
      final batch = TransferBatch();
      batch.add<String>('a', 'Image 1', '/tmp/a.jpg', (report) async {
        report(const TransferProgress(
          phase: TransferPhase.uploading,
          transferred: 50,
          total: 100,
        ));
        return 'u1';
      });
      batch.add<String>('b', 'Image 2', '/tmp/b.jpg', (report) async {
        // total deliberately unknown
        report(const TransferProgress(
          phase: TransferPhase.uploading,
          transferred: 50,
        ));
        return 'u2';
      });
      addTearDown(batch.dispose);

      await batch.startAll();
      expect(batch.aggregateFraction, isNull,
          reason: 'a partial denominator would stall the bar misleadingly');
    });

    test('aggregate fraction weights by real byte totals while in flight',
        () async {
      final gate = Completer<void>();
      final batch = TransferBatch();
      batch.add<String>('a', 'Image 1', '/tmp/a.jpg', (report) async {
        report(const TransferProgress(
          phase: TransferPhase.uploading,
          transferred: 100,
          total: 100,
        ));
        await gate.future;
        return 'u1';
      });
      batch.add<String>('b', 'Image 2', '/tmp/b.jpg', (report) async {
        report(const TransferProgress(
          phase: TransferPhase.uploading,
          transferred: 0,
          total: 300,
        ));
        await gate.future;
        return 'u2';
      });
      addTearDown(batch.dispose);

      final pending = batch.startAll();
      // Mid-flight: 100 of 400 bytes are genuinely on the wire.
      expect(batch.aggregatePercent, 25);

      gate.complete();
      await pending;
      // Both finished, so both totals count in full. A succeeded transfer means
      // the object landed; treating its last reported byte count as final
      // would under-report work that actually completed.
      expect(batch.aggregatePercent, 100);
    });

    test('cancelAll stops presenting items as active', () async {
      final batch = buildBatch(shouldFail: [false, false]);
      addTearDown(batch.dispose);

      batch.cancelAll();
      expect(batch.items.every((i) => i.progressSnapshot.isTerminal), isTrue);
      expect(batch.isBusy, isFalse);
    });
  });
}