import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

/// Lifecycle of one transfer, whether bytes are moving or work is being done
/// on them.
///
/// [preparing] and [processing] deliberately carry no byte count of their own:
/// they are the phases where the honest answer is "working", not "62%". Only
/// [uploading] and [downloading] move [TransferProgress.transferred], and only
/// when the platform actually reports bytes.
enum TransferPhase {
  /// Queued, nothing has started yet.
  queued,

  /// Reading the file, decoding dimensions, compressing or resizing. The
  /// original bytes are known here but they are not the bytes being sent, so
  /// this phase never claims a percentage.
  preparing,

  /// Bytes are on the wire.
  uploading,

  /// Bytes are arriving.
  downloading,

  /// Bytes are done; the server is persisting, deriving variants or indexing.
  processing,

  succeeded,

  failed,

  cancelled,
}

/// A snapshot of one transfer's progress, derived entirely from real work.
///
/// The central rule this type exists to enforce: [fraction] returns `null`
/// when the total is unknown, and the UI must render that as an indeterminate
/// indicator. A progress bar is only ever given a number that came from an
/// actual byte count or an actual state change — never from a timer, and never
/// interpolated toward a guessed total.
class TransferProgress {
  final TransferPhase phase;

  /// Bytes moved so far. Meaningful for [TransferPhase.uploading] and
  /// [TransferPhase.downloading]; carries over to [TransferPhase.succeeded]
  /// so a finished row can still show "2.4 MB".
  final int transferred;

  /// Total bytes, or null when the platform did not tell us.
  ///
  /// Null is common and correct: a chunked response, a multipart POST or an
  /// API that only reports completion gives no denominator. The UI shows an
  /// indeterminate bar in that case rather than inventing one.
  final int? total;

  /// Why the transfer failed. Never rendered verbatim — callers map it to a
  /// translated, actionable message.
  final TransferFailure? failure;

  const TransferProgress({
    this.phase = TransferPhase.queued,
    this.transferred = 0,
    this.total,
    this.failure,
  });

  const TransferProgress.queued()
      : phase = TransferPhase.queued,
        transferred = 0,
        total = null,
        failure = null;

  const TransferProgress.preparing({this.total})
      : phase = TransferPhase.preparing,
        transferred = 0,
        failure = null;

  const TransferProgress.processing({this.transferred = 0, this.total})
      : phase = TransferPhase.processing,
        failure = null;

  const TransferProgress.succeeded({required this.transferred, this.total})
      : phase = TransferPhase.succeeded,
        failure = null;

  const TransferProgress.failed({
    required this.failure,
    this.transferred = 0,
    this.total,
  }) : phase = TransferPhase.failed;

  const TransferProgress.cancelled({this.transferred = 0, this.total})
      : phase = TransferPhase.cancelled,
        failure = null;

  /// 0..1, or `null` when the total is unknown.
  ///
  /// A null here is the signal for the UI to go indeterminate. Returning 0
  /// instead would draw a determinate bar sitting at zero, which reads as
  /// "stuck" and is exactly the kind of dishonest progress this type is
  /// built to avoid.
  double? get fraction {
    final t = total;
    if (t == null || t <= 0) return null;
    if (transferred <= 0) return 0.0;
    return math.min(1.0, transferred / t);
  }

  /// 0..100, or `null` when [fraction] is null.
  int? get percent {
    final f = fraction;
    return f == null ? null : (f * 100).round().clamp(0, 100);
  }

  /// True only while bytes are actually moving.
  bool get isTransferring =>
      phase == TransferPhase.uploading || phase == TransferPhase.downloading;

  /// True while the transfer has neither succeeded nor stopped.
  bool get isActive =>
      !isTerminal && phase != TransferPhase.queued;

  bool get isTerminal =>
      phase == TransferPhase.succeeded ||
      phase == TransferPhase.failed ||
      phase == TransferPhase.cancelled;

  bool get isFailed => phase == TransferPhase.failed;

  bool get isSucceeded => phase == TransferPhase.succeeded;

  /// True while the app is doing work whose duration is genuinely unknown and
  /// must not be dressed up as a percentage.
  bool get isIndeterminate =>
      fraction == null &&
      (phase == TransferPhase.preparing || isTransferring ||
          phase == TransferPhase.processing);

  TransferProgress copyWith({
    TransferPhase? phase,
    int? transferred,
    int? total,
    TransferFailure? failure,
  }) {
    return TransferProgress(
      phase: phase ?? this.phase,
      transferred: transferred ?? this.transferred,
      total: total ?? this.total,
      failure: failure ?? this.failure,
    );
  }
}

/// Why a transfer stopped, in terms the UI can act on.
///
/// Modelled as a closed set rather than a free-form string so a screen can map
/// each cause to specific copy and a specific recovery affordance. "Something
/// went wrong" is not an acceptable member of this enum.
enum TransferFailureKind {
  /// Device believes it has no usable network path.
  offline,

  /// The socket died mid-transfer. Safe to retry: the PUT is idempotent
  /// because it targets a presigned URL for a freshly minted key.
  interrupted,

  /// The caller aborted deliberately.
  cancelled,

  /// The device or browser denied access to the file or camera roll.
  permissionDenied,

  /// The file exceeds the limit the app or the server enforces.
  tooLarge,

  /// Extension or MIME type the upload path does not accept.
  unsupportedType,

  /// The server answered, but not with success.
  server,

  /// The id token expired and the session has to be re-established.
  authExpired,

  /// Local file vanished or became unreadable between selection and send.
  unreadableSource,

  /// Deliberately unclassified. Carries a technical message for telemetry.
  unknown,
}

/// A failure plus the human-facing detail needed to explain it.
class TransferFailure implements Exception {
  final TransferFailureKind kind;

  /// Technical text for logs and error monitoring. Never shown to a seller.
  final String message;

  /// HTTP status when [kind] is [TransferFailureKind.server], else null. Lets
  /// the UI distinguish "try again" from "this will never work".
  final int? statusCode;

  const TransferFailure({
    required this.kind,
    required this.message,
    this.statusCode,
  });

  @override
  String toString() => 'TransferFailure($kind, $message, status: $statusCode)';

  /// Classifies a thrown object into a [TransferFailure].
  ///
  /// Ordering matters: the explicit kinds are checked before the fallbacks so a
  /// `SocketException` is never reported as a generic server error just because
  /// a wrapped HTTP error also mentioned the network.
  factory TransferFailure.from(Object error, {int? statusCode}) {
    final text = error.toString();

    if (error is TransferFailure) return error;

    // Socket-level failures surface as SocketException, HandshakeException or
    // a ClientException wrapping them.
    if (error is SocketException ||
        error is HandshakeException ||
        error is HttpException ||
        text.contains('SocketException') ||
        text.contains('Connection closed') ||
        text.contains('Connection reset') ||
        text.contains('Network is unreachable') ||
        text.contains('Failed host lookup')) {
      return TransferFailure(
        kind: TransferFailureKind.interrupted,
        message: text,
        statusCode: statusCode,
      );
    }

    if (error is FileSystemException) {
      return TransferFailure(
        kind: TransferFailureKind.unreadableSource,
        message: text,
        statusCode: statusCode,
      );
    }

    if (error is TimeoutException) {
      return TransferFailure(
        kind: TransferFailureKind.interrupted,
        message: text,
        statusCode: statusCode,
      );
    }

    final code = statusCode ?? _statusFromMessage(text);
    if (code == 401 || code == 403) {
      return TransferFailure(
        kind: TransferFailureKind.authExpired,
        message: text,
        statusCode: code,
      );
    }
    if (code == 413) {
      return TransferFailure(
        kind: TransferFailureKind.tooLarge,
        message: text,
        statusCode: code,
      );
    }
    if (code != null && code >= 400) {
      return TransferFailure(
        kind: TransferFailureKind.server,
        message: text,
        statusCode: code,
      );
    }

    if (text.contains('Permission denied') ||
        text.contains('photo_manager') ||
        text.contains('PhotoAccessDenied')) {
      return TransferFailure(
        kind: TransferFailureKind.permissionDenied,
        message: text,
      );
    }

    return TransferFailure(
      kind: TransferFailureKind.unknown,
      message: text,
      statusCode: statusCode,
    );
  }

  static int? _statusFromMessage(String text) {
    // `NetworkError` and `http` both embed the code in their message; pull it
    // out rather than making every call site pass it twice.
    for (final marker in const ['HTTP ', 'status code ', 'statusCode: ']) {
      final i = text.indexOf(marker);
      if (i == -1) continue;
      final rest = text.substring(i + marker.length);
      final digits =
          rest.split(RegExp(r'\D')).firstWhere((s) => s.isNotEmpty, orElse: () => '');
      final parsed = int.tryParse(digits);
      if (parsed != null && parsed >= 100 && parsed < 600) return parsed;
    }
    return null;
  }

  /// Whether offering a retry button makes sense.
  ///
  /// A permission denial or an unsupported file type will fail identically on
  /// a second attempt, so showing "Retry" there teaches the seller that the
  /// button is broken.
  bool get isRetryable => switch (kind) {
        TransferFailureKind.permissionDenied => false,
        TransferFailureKind.unsupportedType => false,
        TransferFailureKind.unreadableSource => false,
        TransferFailureKind.tooLarge => false,
        TransferFailureKind.cancelled => true,
        _ => true,
      };
}