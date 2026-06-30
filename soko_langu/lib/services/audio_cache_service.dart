import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

class AudioCacheService {
  static final AudioCacheService _instance = AudioCacheService._();
  factory AudioCacheService() => _instance;
  AudioCacheService._();

  Directory? _cacheDir;

  Future<void> init() async {
    if (_cacheDir != null) return;
    final appDir = await getApplicationDocumentsDirectory();
    _cacheDir = Directory('${appDir.path}/audio_cache');
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
  }

  /// Synchronous cache lookup — non-null only if cache dir already initialized.
  String? tryGetCached(String url) {
    if (url.startsWith('file://') || url.startsWith('content://')) return url;
    final key = url.hashCode.toString();
    final dir = _cacheDir;
    if (dir == null) return null;
    final path = '${dir.path}/$key.mp3';
    return File(path).existsSync() ? 'file:///$path' : null;
  }

  /// Async cache lookup — initializes cache dir if needed.
  Future<String?> get(String url) async {
    if (url.startsWith('file://') || url.startsWith('content://')) return url;
    final cached = tryGetCached(url);
    if (cached != null) return cached;
    return await _download(url);
  }

  /// Download a URL for offline playback.
  Future<bool> cacheUrl(String url) async {
    if (url.startsWith('file://') || url.startsWith('content://')) return true;
    if ((tryGetCached(url)) != null) return true;
    final result = await _download(url);
    return result != null;
  }

  Future<String?> _download(String url) async {
    try {
      final dir = _cacheDir ?? await _getCacheDir();
      final key = url.hashCode.toString();
      final file = File('${dir.path}/$key.mp3');
      if (await file.exists()) return 'file:///${file.path}';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        return 'file:///${file.path}';
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Directory> _getCacheDir() async {
    await init();
    return _cacheDir!;
  }

  Future<bool> isCached(String url) async {
    final key = url.hashCode.toString();
    final dir = _cacheDir ?? await _getCacheDir();
    return File('${dir.path}/$key.mp3').exists();
  }

  Future<void> clearCache() async {
    final dir = _cacheDir ?? await _getCacheDir();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    _cacheDir = null;
  }

  Future<int> cacheSize() async {
    final dir = _cacheDir ?? await _getCacheDir();
    if (!await dir.exists()) return 0;
    int size = 0;
    await for (var f in dir.list()) {
      if (f is File) size += await f.length();
    }
    return size;
  }
}