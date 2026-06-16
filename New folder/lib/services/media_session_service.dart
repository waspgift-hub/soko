import 'dart:async';
import 'package:flutter/services.dart';

class MediaSessionService {
  static final MediaSessionService instance = MediaSessionService._();
  MediaSessionService._();

  final MethodChannel _channel = const MethodChannel('soko_lang/media_session');
  final EventChannel _events = const EventChannel('soko_lang/media_events');

  final _stateController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get stateStream => _stateController.stream;

  Map<String, dynamic> _currentState = {
    'playing': false,
    'currentIndex': -1,
    'position': 0,
    'duration': 0,
    'repeatMode': 0,
    'shuffle': false,
  };
  Map<String, dynamic> get currentState => _currentState;

  bool get isPlaying => _currentState['playing'] as bool? ?? false;
  int get currentIndex => _currentState['currentIndex'] as int? ?? -1;
  int get positionMs => _currentState['position'] as int? ?? 0;
  int get durationMs => _currentState['duration'] as int? ?? 0;

  StreamSubscription<dynamic>? _eventSub;

  void init() {
    _eventSub?.cancel();
    _eventSub = _events.receiveBroadcastStream().listen((data) {
      if (data is Map) {
        _currentState = Map<String, dynamic>.from(data as Map);
        _stateController.add(_currentState);
      }
    });
  }

  Future<void> initPlaylist(List<Map<String, dynamic>> songs) async {
    await _channel.invokeMethod('initPlaylist', {'songs': songs});
  }

  Future<void> playAtIndex(int index) async {
    await _channel.invokeMethod('playAtIndex', {'index': index});
  }

  Future<void> play() async {
    await _channel.invokeMethod('play');
  }

  Future<void> pause() async {
    await _channel.invokeMethod('pause');
  }

  Future<void> togglePlayPause() async {
    await _channel.invokeMethod('togglePlayPause');
  }

  Future<void> seekTo(Duration position) async {
    await _channel.invokeMethod('seekTo', {'positionMs': position.inMilliseconds});
  }

  Future<void> setRepeatMode(int mode) async {
    await _channel.invokeMethod('setRepeatMode', {'mode': mode});
  }

  Future<void> setShuffle(bool enabled) async {
    await _channel.invokeMethod('setShuffle', {'enabled': enabled});
  }

  Future<void> next() async {
    await _channel.invokeMethod('next');
  }

  Future<void> previous() async {
    await _channel.invokeMethod('previous');
  }

  Future<void> stop() async {
    await _channel.invokeMethod('stop');
  }

  void dispose() {
    _eventSub?.cancel();
  }
}
