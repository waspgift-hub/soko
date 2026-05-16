import 'dart:io';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';

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
    if (error.message?.contains('PERMISSION_DENIED') == true) {
      return 'You do not have permission to perform this action.';
    }
    if (error.message?.contains('UNAVAILABLE') == true ||
        error.message?.contains('UNAUTHENTICATED') == true) {
      return 'Poor internet connection. Please check your network.';
    }
    if (error.message?.contains('NOT_FOUND') == true) {
      return 'The requested information was not found.';
    }
    if (error.message?.contains('ALREADY_EXISTS') == true) {
      return 'This item already exists.';
    }
    return error.message ?? 'Poor internet connection. Please check your network.';
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
  if (msg.contains('PERMISSION_DENIED') || msg.contains('permission')) {
    return 'You do not have permission to perform this action.';
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
