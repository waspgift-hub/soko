import 'dart:io';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';

/// Classifies Firestore / network failures for UI messaging.
enum FirestoreErrorKind {
  network,
  permission,
  missingIndex,
  other,
}

/// Translation keys for user-facing error messages. UI renders them through
/// `context.trError()` so errors follow the app language, not hardcoded text.
class ErrorKeys {
  static const poorNetwork = 'error_poor_network';
  static const noPermission = 'error_no_permission';
  static const notFound = 'error_not_found';
  static const alreadyExists = 'error_already_exists';
  static const indexBuilding = 'error_index_building';
  static const sessionExpired = 'error_session_expired';
  static const generic = 'error_generic';
  static const noAccount = 'error_no_account';
  static const wrongPassword = 'error_wrong_password';
  static const invalidEmail = 'error_invalid_email';
  static const accountDisabled = 'error_account_disabled';
  static const emailInUse = 'error_email_in_use';
  static const operationNotAllowed = 'error_operation_not_allowed';
  static const weakPassword = 'error_weak_password';
  static const tooManyAttempts = 'error_too_many_attempts';
  static const invalidCredentials = 'error_invalid_credentials';
  static const timeout = 'error_timeout';
}

class FirestoreErrorInfo {
  final FirestoreErrorKind kind;
  final String raw;

  const FirestoreErrorInfo({required this.kind, required this.raw});
}

FirestoreErrorInfo classifyFirestoreError(dynamic error) {
  final msg = error is FirebaseException
      ? '${error.code} ${error.message ?? ''}'
      : error.toString();

  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return FirestoreErrorInfo(kind: FirestoreErrorKind.permission, raw: msg);
      case 'failed-precondition':
        return FirestoreErrorInfo(kind: FirestoreErrorKind.missingIndex, raw: msg);
      case 'unavailable':
      case 'deadline-exceeded':
        return FirestoreErrorInfo(kind: FirestoreErrorKind.network, raw: msg);
    }
  }

  final lower = msg.toLowerCase();
  if (lower.contains('permission-denied') ||
      lower.contains('permission_denied') ||
      lower.contains('caller does not have permission')) {
    return FirestoreErrorInfo(kind: FirestoreErrorKind.permission, raw: msg);
  }
  if (lower.contains('failed-precondition') ||
      lower.contains('requires an index')) {
    return FirestoreErrorInfo(kind: FirestoreErrorKind.missingIndex, raw: msg);
  }
  if (lower.contains('unavailable') ||
      lower.contains('network') ||
      lower.contains('timeout') ||
      lower.contains('timed out') ||
      lower.contains('socketexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('connection refused')) {
    return FirestoreErrorInfo(kind: FirestoreErrorKind.network, raw: msg);
  }

  return FirestoreErrorInfo(kind: FirestoreErrorKind.other, raw: msg);
}

class NetworkError implements Exception {
  final String message;
  final String userMessage;
  final dynamic originalError;

  NetworkError({
    required this.message,
    required this.userMessage,
    this.originalError,
  });

  @override
  String toString() => userMessage;
}

/// Maps an error to a translation KEY (see [ErrorKeys]). The UI renders it via
/// `context.trError()` so the message matches the app language. Kept key-based
/// (not a BuildContext) so services without context can produce it.
String translateError(dynamic error) {
  if (error is NetworkError) return error.userMessage;

  if (error is SocketException) {
    return ErrorKeys.poorNetwork;
  }
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return ErrorKeys.noPermission;
      case 'unavailable':
      case 'deadline-exceeded':
        return ErrorKeys.poorNetwork;
      case 'not-found':
        return ErrorKeys.notFound;
      case 'already-exists':
        return ErrorKeys.alreadyExists;
      case 'failed-precondition':
        return ErrorKeys.indexBuilding;
      case 'unauthenticated':
        return ErrorKeys.sessionExpired;
      default:
        return error.message ?? ErrorKeys.generic;
    }
  }
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'user-not-found':
        return ErrorKeys.noAccount;
      case 'wrong-password':
        return ErrorKeys.wrongPassword;
      case 'invalid-email':
        return ErrorKeys.invalidEmail;
      case 'user-disabled':
        return ErrorKeys.accountDisabled;
      case 'email-already-in-use':
        return ErrorKeys.emailInUse;
      case 'operation-not-allowed':
        return ErrorKeys.operationNotAllowed;
      case 'weak-password':
        return ErrorKeys.weakPassword;
      case 'network-request-failed':
        return ErrorKeys.poorNetwork;
      case 'too-many-requests':
        return ErrorKeys.tooManyAttempts;
      case 'invalid-credential':
        return ErrorKeys.invalidCredentials;
      default:
        return error.message ?? ErrorKeys.poorNetwork;
    }
  }
  if (error is TimeoutException) {
    return ErrorKeys.timeout;
  }
  if (error is FormatException) {
    return ErrorKeys.generic;
  }

  final msg = error.toString();
  if (msg.contains('UNAVAILABLE') ||
      msg.contains('network') ||
      msg.contains('timeout') ||
      msg.contains('timed out') ||
      msg.contains('SocketException') ||
      msg.contains('Failed host lookup') ||
      msg.contains('Connection refused')) {
    return ErrorKeys.poorNetwork;
  }
  if (msg.contains('PERMISSION_DENIED') ||
      msg.contains('permission') ||
      msg.contains('caller does not have permission')) {
    return ErrorKeys.noPermission;
  }

  return ErrorKeys.generic;
}

Future<T> guardNetwork<T>(Future<T> Function() operation) async {
  try {
    return await operation();
  } catch (e) {
    final friendly = translateError(e);
    throw NetworkError(
      message: e.toString(),
      userMessage: friendly,
      originalError: e,
    );
  }
}
