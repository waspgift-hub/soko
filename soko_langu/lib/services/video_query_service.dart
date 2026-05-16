import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class VideoQueryService {
  static const _channel = MethodChannel('soko_lang/video_query');

  static Future<List<Map<String, dynamic>>> queryVideos() async {
    try {
      final result = await _channel.invokeMethod('queryVideos');
      return List<Map<String, dynamic>>.from(result as List);
    } catch (e) {
      debugPrint('VideoQueryService.queryVideos: $e');
      return [];
    }
  }
}
