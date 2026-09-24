import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Handles Gallery → Soko Vibe share intents (image/video).
///
/// Android: intercepts ACTION_SEND / ACTION_SEND_MULTIPLE via MainActivity.
/// iOS: share extension path is prepared but gracefully degrades if not present.
///
/// Media is never auto-published — it is attached to the Create Product composer
/// and the user must press Publish.
class ReceiveShareService {
  ReceiveShareService._();
  static final ReceiveShareService instance = ReceiveShareService._();

  static const MethodChannel _channel = MethodChannel('soko/share_receive');
  static const String _pendingMediaKey = 'pending_share_media';
  static const int maxImages = 5;
  static const int maxVideoBytes = 100 * 1024 * 1024; // 100 MB
  static const int maxImageBytes = 20 * 1024 * 1024; // 20 MB

  List<String> _pendingPaths = [];
  bool _initialized = false;
  StreamSubscription? _sub;

  /// Callback when media arrives while app is running.
  void Function(List<String> paths)? onMediaReceived;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    // pull initial shared media that launched the app
    try {
      final initial = await _channel.invokeMethod<List<dynamic>>('getInitialMedia');
      if (initial != null && initial.isNotEmpty) {
        final paths = initial.map((e) => e.toString()).toList();
        await _handleIncoming(paths);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('ReceiveShareService getInitialMedia failed: $e');
    }
    // listen for warm-start shares
    try {
      const eventChannel = EventChannel('soko/share_receive_stream');
      _sub = eventChannel.receiveBroadcastStream().listen((event) {
        if (event is List) {
          final paths = event.map((e) => e.toString()).toList();
          unawaited(_handleIncoming(paths));
        }
      }, onError: (e) {
        if (kDebugMode) debugPrint('ReceiveShareService stream error: $e');
      });
    } catch (_) {
      // fallback to method channel polling
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onMediaShared') {
          final args = call.arguments;
          if (args is List) {
            await _handleIncoming(args.map((e) => e.toString()).toList());
          }
        }
      });
    }
    // restore persisted pending media (e.g. shared while logged out)
    await _restorePending();
  }

  Future<void> _handleIncoming(List<String> rawPaths) async {
    final validated = await _validateAndFilter(rawPaths);
    if (validated.isEmpty) return;
    _pendingPaths = validated;
    await _persistPending(validated);
    _trackMediaReceived(validated);
    onMediaReceived?.call(validated);
  }

  Future<List<String>> _validateAndFilter(List<String> paths) async {
    final out = <String>[];
    for (final p in paths) {
      if (p.isEmpty) continue;
      // limit total
      if (out.length >= maxImages) break;
      final file = File(p);
      bool exists = false;
      try {
        exists = await file.exists();
      } catch (_) {}
      if (!exists) continue;
      // size + type validation — don't trust extension/MIME alone
      final ext = p.split('.').last.toLowerCase();
      final isVideo = ['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp', 'm4v'].contains(ext);
      final isImage = ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'gif'].contains(ext);
      // if extension unknown, probe via header bytes
      bool allowed = isVideo || isImage;
      if (!allowed) {
        // try header magic
        try {
          final bytes = await file.openRead(0, 12).first;
          if (bytes.length >= 4) {
            // JPEG FF D8 FF, PNG 89 50 4E 47, WEBP RIFF....WEBP, MP4 ftyp
            if (bytes[0] == 0xFF && bytes[1] == 0xD8) allowed = true;
            if (bytes[0] == 0x89 && bytes[1] == 0x50) allowed = true;
            if (bytes[0] == 0x52 && bytes[1] == 0x49) allowed = true; // RIFF
            if (bytes.length >= 8 &&
                String.fromCharCodes(bytes.sublist(4, 8)) == 'ftyp') allowed = true;
          }
        } catch (_) {}
      }
      if (!allowed) continue;
      try {
        final size = await file.length();
        if (isVideo && size > maxVideoBytes) continue;
        if (isImage && size > maxImageBytes) continue;
        if (size == 0) continue;
      } catch (_) {
        continue;
      }
      out.add(p);
    }
    return out;
  }

  Future<void> _persistPending(List<String> paths) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_pendingMediaKey, paths);
    } catch (_) {}
  }

  Future<void> _restorePending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_pendingMediaKey);
      if (list != null && list.isNotEmpty) {
        _pendingPaths = list;
      }
    } catch (_) {}
  }

  Future<void> clearPending() async {
    _pendingPaths = [];
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingMediaKey);
    } catch (_) {}
  }

  List<String> get pendingPaths => List.unmodifiable(_pendingPaths);
  bool get hasPending => _pendingPaths.isNotEmpty;

  /// Consumes pending and clears storage — call after attaching to composer.
  List<String> consumePending() {
    final copy = List<String>.from(_pendingPaths);
    unawaited(clearPending());
    _pendingPaths = [];
    return copy;
  }

  void _trackMediaReceived(List<String> paths) {
    if (kDebugMode) debugPrint('Analytics: share_to_sell_opened count=${paths.length}');
    // TODO wire to analytics — never log raw paths
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
