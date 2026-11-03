import 'dart:io';
import 'package:flutter/services.dart';

/// Pins a chat shortcut to the Android home screen.
/// Returns `true` if the shortcut was pinned successfully, `false` on
/// unsupported platforms or failure.
Future<bool> pinChatShortcut({
  required String receiverId,
  required String receiverName,
}) async {
  if (!Platform.isAndroid) return false;
  try {
    final result = await const MethodChannel('soko_lang/shortcut')
        .invokeMethod<bool>('pinShortcut', {
      'receiverId': receiverId,
      'receiverName': receiverName,
    });
    return result ?? false;
  } on MissingPluginException {
    return false;
  }
}
