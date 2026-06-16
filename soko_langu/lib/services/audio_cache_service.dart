import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

class AudioCacheService {
  static final AudioCacheService _instance = AudioCacheService._();
  factory AudioCacheService() => _instance;
  AudioCacheService._();

  Directory? _cacheDir;

  Future<Directory> _getCacheDir() async {
    if (_cacheDir != null) return _cacheDir!;
    final appDir = await getApplicationDocumentsDirectory();
    _cacheDir = Directory('${appDir.path}/audio_cache');
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
    return _cacheDir!;
  }

  String _cacheKey(String url) {
    return url.hashCode.toString();
  }

  String? _cachedPath(String url) {
    final key = _cacheKey(url);
    final dir = _cacheDir;
    if (dir == null) return null;
    final path = '${dir.path}/$key.mp3';
    return File(path).existsSync() ? path : null;
  }

  Future<String?> get(String url) async {
    final cached = _cachedPath(url);
    if (cached != null) return cached;
    return await _download(url);
  }

  Future<String?> _download(String url) async {
    try {
      final dir = await _getCacheDir();
      final key = _cacheKey(url);
      final file = File('${dir.path}/$key.mp3');
      if (await file.exists()) return file.path;
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        return file.path;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> isCached(String url) async {
    final dir = await _getCacheDir();
    final key = _cacheKey(url);
    return File('${dir.path}/$key.mp3').exists();
  }

  Future<void> clearCache() async {
    final dir = await _getCacheDir();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    _cacheDir = null;
  }

  Future<int> cacheSize() async {
    final dir = await _getCacheDir();
    if (!await dir.exists()) return 0;
    int size = 0;
    await for (var f in dir.list()) {
      if (f is File) size += await f.length();
    }
    return size;
  }
}