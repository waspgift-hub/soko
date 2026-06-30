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

String translateError(dynamic error) {
  if (error is NetworkError) return error.userMessage;

  if (error is SocketException) {
    return 'Poor internet connection. Please check your network.';
  }
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return 'You do not have permission to perform this action. Please try logging out and back in.';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'Poor internet connection. Please check your network.';
      case 'not-found':
        return 'The requested information was not found.';
      case 'already-exists':
        return 'This item already exists.';
      case 'failed-precondition':
        return 'The database index is still building. Please try again shortly.';
      case 'unauthenticated':
        return 'Your session has expired. Please sign in again.';
      default:
        return error.message ?? 'Something went wrong. Please try again.';
    }
  }
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'invalid-email':
        return 'The email address is not valid.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'email-already-in-use':
        return 'An account with this email already exists.';
      case 'operation-not-allowed':
        return 'This sign-in method is not enabled.';
      case 'weak-password':
        return 'The password is too weak. Use at least 6 characters.';
      case 'network-request-failed':
        return 'Poor internet connection. Please check your network.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'invalid-credential':
        return 'Invalid login credentials. Please try again.';
      default:
        return error.message ?? 'Poor internet connection. Please check your network.';
    }
  }
  if (error is TimeoutException) {
    return 'Request timed out. Poor internet connection.';
  }
  if (error is FormatException) {
    return 'Something went wrong. Please try again.';
  }

  final msg = error.toString();
  if (msg.contains('UNAVAILABLE') ||
      msg.contains('network') ||
      msg.contains('timeout') ||
      msg.contains('timed out') ||
      msg.contains('SocketException') ||
      msg.contains('Failed host lookup') ||
      msg.contains('Connection refused')) {
    return 'Poor internet connection. Please check your network.';
  }
  if (msg.contains('PERMISSION_DENIED') ||
      msg.contains('permission') ||
      msg.contains('caller does not have permission')) {
    return 'You do not have permission to perform this action. Please try logging out and back in.';
  }

  return 'Something went wrong. Please try again.';
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
