import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Pins an Android home-screen shortcut. [iconUrl] (profile/product image) is
/// downloaded and passed as a local file so the shortcut uses that image.
/// Returns `true` when pinned, `false` on unsupported platforms or failure.
Future<bool> pinShortcut({
  required String id,
  required String label,
  required String route,
  String type = 'chat',
  String? iconUrl,
}) async {
  if (!Platform.isAndroid) return false;
  String? iconPath;
  if (iconUrl != null && iconUrl.trim().isNotEmpty) {
    iconPath = await _cacheShortcutIcon(id: id, type: type, url: iconUrl.trim());
  }
  try {
    final result = await const MethodChannel('soko_lang/shortcut').invokeMethod<bool>(
      'pinShortcut',
      {'id': id, 'label': label, 'route': route, 'type': type, 'iconPath': ?iconPath},
    );
    return result ?? false;
  } on MissingPluginException {
    return false;
  } catch (e) {
    debugPrint('pinShortcut failed: $e');
    return false;
  }
}

/// Pins a chat shortcut to the Android home screen.
Future<bool> pinChatShortcut({
  required String receiverId,
  required String receiverName,
  String? iconUrl,
}) async {
  return pinShortcut(
    id: receiverId,
    label: receiverName,
    route: '/chat/$receiverId',
    type: 'chat',
    iconUrl: iconUrl,
  );
}

/// Pins a profile shortcut using the profile owner's image and a deep-link
/// route that carries the profile user ID.
Future<bool> pinProfileShortcut({
  required String userId,
  required String displayName,
  String? iconUrl,
}) async {
  return pinShortcut(
    id: userId,
    label: displayName.isEmpty ? 'Soko Vibe' : displayName,
    route: '/public-profile/$userId',
    type: 'profile',
    iconUrl: iconUrl,
  );
}

Future<String?> _cacheShortcutIcon({
  required String id,
  required String type,
  required String url,
}) async {
  try {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return null;
    }
    final res = await http.get(uri).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
    // Keep shortcut icons small to avoid oversized launcher resources.
    if (res.bodyBytes.length > 2 * 1024 * 1024) return null;
    final dir = await getTemporaryDirectory();
    final safeId = id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final ext = _iconExt(res.headers['content-type'], url);
    final file = File('${dir.path}/shortcut_${type}_$safeId.$ext');
    await file.writeAsBytes(res.bodyBytes, flush: true);
    return file.path;
  } catch (e) {
    debugPrint('Shortcut icon cache failed: $e');
    return null;
  }
}

String _iconExt(String? contentType, String url) {
  final ct = (contentType ?? '').toLowerCase();
  if (ct.contains('png')) return 'png';
  if (ct.contains('webp')) return 'webp';
  if (ct.contains('jpeg') || ct.contains('jpg')) return 'jpg';
  final lower = url.toLowerCase();
  if (lower.contains('.png')) return 'png';
  if (lower.contains('.webp')) return 'webp';
  return 'jpg';
}
