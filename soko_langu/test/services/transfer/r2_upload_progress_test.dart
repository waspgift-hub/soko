import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/services/r2_media_service.dart';

/// Exercises the real byte-accounting in [R2MediaService] against a local HTTP
/// server standing in for the presigned R2 endpoint.
///
/// The point of these tests is §4/§23 of the brief: the numbers the UI shows
/// must come from bytes that actually crossed a socket. A stubbed uploader
/// would keep passing even if the real one regressed to a timer or went back to
/// a `http.put` that reports nothing, so the transfer runs over real TCP here.
void main() {
  late HttpServer server;
  late Directory workDir;
  late List<int> received;
  late int responseStatus;
  late String? observedType;
  late int? observedLength;
  late bool abortMidStream;
  late String presigned;

  setUp(() async {
    received = <int>[];
    responseStatus = HttpStatus.ok;
    observedType = null;
    observedLength = null;
    abortMidStream = false;

    workDir = await Directory.systemTemp.createTemp('soko_transfer_test');

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    presigned = 'http://127.0.0.1:${server.port}/upload';

    // One listener for the whole group: HttpServer allows a single `listen`,
    // so per-test behaviour is switched through these variables.
    unawaitedListen(server, (request) async {
      observedType ??= request.headers.value('content-type');
      observedLength = request.contentLength;

      if (abortMidStream) {
        // Accept the connection, read nothing, then destroy the socket. The
        // client must see an error rather than a completed upload.
        final socket = await request.response.detachSocket();
        socket.destroy();
        return;
      }

      await for (final chunk in request) {
        received.addAll(chunk);
      }
      request.response.statusCode = responseStatus;
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    // Windows keeps a handle on a just-read file for a moment; a failed
    // cleanup must not fail the test that produced it.
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        if (workDir.existsSync()) await workDir.delete(recursive: true);
        break;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  });

  Future<File> tempFile(String name, int bytes) async {
    final f = File('${workDir.path}/$name');
    await f.writeAsBytes(List<int>.filled(bytes, 65));
    return f;
  }

  Future<void> put(
    File file, {
    String? url,
    void Function(int sent, int total)? onProgress,
  }) =>
      R2MediaService.putToR2ForTesting(
        url: url ?? presigned,
        file: file,
        contentType: 'application/octet-stream',
        onProgress: onProgress,
      );

  group('R2MediaService byte progress', () {
    test('reports real byte counts against the real file length', () async {
      final file = await tempFile('a.bin', 40 * 1024);
      final reports = <(int, int)>[];

      await put(file, onProgress: (sent, total) => reports.add((sent, total)));

      expect(reports, isNotEmpty, reason: 'no progress was reported at all');
      expect(
        reports.first.$2,
        40 * 1024,
        reason: 'the total must be the real file length, never an estimate',
      );

      // Monotonic and never past the total.
      var previous = -1;
      for (final (sent, total) in reports) {
        expect(sent, greaterThanOrEqualTo(previous),
            reason: 'progress went backwards: $previous then $sent');
        expect(sent, lessThanOrEqualTo(total));
        previous = sent;
      }
      expect(reports.last.$1, 40 * 1024);
      expect(reports.last.$2, 40 * 1024);

      // And those bytes really crossed the socket.
      expect(received.length, 40 * 1024);
    });

    test('progress never decreases across a multi-chunk transfer', () async {
      final file = await tempFile('big.bin', 600 * 1024);
      final reports = <int>[];

      await put(file, onProgress: (sent, _) => reports.add(sent));

      expect(reports.length, greaterThan(2),
          reason: 'a 600KB transfer should produce several updates');
      for (var i = 1; i < reports.length; i++) {
        expect(reports[i], greaterThanOrEqualTo(reports[i - 1]));
      }
      expect(received.length, 600 * 1024);
    });

    test('a single-chunk transfer still ends at exactly its total', () async {
      // Only the authoritative post-response report is emitted when the
      // throttle suppresses the intermediate one, so the last report must be
      // the real total rather than whatever the last chunk happened to be.
      final file = await tempFile('tiny.bin', 16);
      final reports = <(int, int)>[];

      await put(file, onProgress: (sent, total) => reports.add((sent, total)));

      expect(reports.last, (16, 16));
      expect(received.length, 16);
    });

    test('sends the declared Content-Type and Content-Length', () async {
      final file = await tempFile('a.webp', 4096);

      await R2MediaService.putToR2ForTesting(
        url: presigned,
        file: file,
        contentType: 'image/webp',
      );

      expect(observedType, 'image/webp');
      expect(observedLength, 4096);
    });

    test('a non-2xx response throws instead of reporting success', () async {
      responseStatus = HttpStatus.forbidden;
      final file = await tempFile('a.bin', 64);
      final reports = <int>[];

      await expectLater(
        put(file, onProgress: (sent, _) => reports.add(sent)),
        throwsA(anything),
      );
      // The failure must not have been reported as a completed transfer.
      expect(reports.every((s) => s <= 64), isTrue);
    });

    test('a connection dropped mid-request fails rather than completing',
        () async {
      abortMidStream = true;
      final file = await tempFile('big.bin', 400 * 1024);
      final reports = <int>[];

      Object? caught;
      try {
        await put(file, onProgress: (sent, _) => reports.add(sent));
      } on Object catch (e) {
        caught = e;
      }

      expect(caught, isNotNull,
          reason: 'a dropped connection must surface as a failure');
      // Never reported as fully sent.
      expect(reports.every((s) => s < 400 * 1024), isTrue,
          reason: 'a partial transfer must not be shown as complete');
    });
  });

  group('content type mapping', () {
    test('extension decides the type stored with the object', () {
      // A mismatch here would make the CDN serve a WebP as image/jpeg.
      expect(R2MediaService.contentTypeForTesting('webp'), 'image/webp');
      expect(R2MediaService.contentTypeForTesting('png'), 'image/png');
      expect(R2MediaService.contentTypeForTesting('jpg'), 'image/jpeg');
      expect(R2MediaService.contentTypeForTesting('jpeg'), 'image/jpeg');
      expect(R2MediaService.contentTypeForTesting('mp4'), 'video/mp4');
    });

    test('an unknown extension falls back to jpeg rather than failing', () {
      expect(R2MediaService.contentTypeForTesting('heic'), 'image/jpeg');
    });
  });
}

/// Starts [server]'s listener without blocking, so `setUp` stays synchronous
/// with respect to the listener registration.
void unawaitedListen(HttpServer server, Future<void> Function(HttpRequest) onRequest) {
  server.listen((request) => onRequest(request));
}