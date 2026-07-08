import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import '../services/audio_handler.dart';

/// Reactive music playback state for the UI layer.
///
/// Listens to [MusicHandler] streams once the handler becomes available
/// (via [musicHandlerFuture]) so there is no polling or retry loop.
class MusicStateNotifier extends ChangeNotifier {
  MusicHandler? _handler;
  bool _initStarted = false;
  StreamSubscription<PlaybackState>? _stateSub;
  StreamSubscription<MediaItem?>? _mediaItemSub;
  StreamSubscription<List<MediaItem>>? _queueSub;

  String _title = '';
  String _artist = '';
  Uri? _artUri;
  String? _videoUrl;
  String? _youtubeVideoId;
  bool _isPlaying = false;
  bool _hasActivePlayback = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  List<MediaItem> _queue = [];
  bool _hasError = false;
  String _lastError = '';
  double _speed = 1.0;
  double _volume = 1.0;
  bool _shuffleEnabled = false;
  String _repeatMode = 'off';

  String get title => _title;
  String get artist => _artist;
  Uri? get artUri => _artUri;
  String? get videoUrl => _videoUrl;
  String? get youtubeVideoId => _youtubeVideoId;
  bool get isPlaying => _isPlaying;
  bool get hasActivePlayback => _hasActivePlayback;
  Duration get position => _position;
  Duration get duration => _duration;
  List<MediaItem> get queue => _queue;
  int get queueLength => _queue.length;
  bool get hasError => _hasError;
  String get lastError => _lastError;
  int? get currentIndex => _handler?.currentIndex;
  double get speed => _speed;
  double get volume => _volume;
  bool get shuffleEnabled => _shuffleEnabled;
  String get repeatMode => _repeatMode;

  double get progress {
    if (_duration.inMilliseconds <= 0) return 0.0;
    return (_position.inMilliseconds / _duration.inMilliseconds)
        .clamp(0.0, 1.0);
  }

  /// Subscribe to the [MusicHandler] once it becomes available.
  /// Safe to call multiple times — only runs once.
  Future<void> init() async {
    if (_initStarted) return;
    _initStarted = true;

    try {
      _handler = await musicHandlerFuture
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('[AUDIO] Notifier: handler not available — $e');
      _hasError = true;
      notifyListeners();
      return;
    }

    _stateSub?.cancel();
    _stateSub = _handler!.playbackState.stream.listen((state) {
      _isPlaying = state.playing;
      _position = state.updatePosition;
      _hasActivePlayback =
          state.processingState != AudioProcessingState.idle &&
          state.processingState != AudioProcessingState.completed;
      _speed = state.speed;
      _shuffleEnabled =
          state.shuffleMode == AudioServiceShuffleMode.all;
      switch (state.repeatMode) {
        case AudioServiceRepeatMode.none:
          _repeatMode = 'off';
        case AudioServiceRepeatMode.one:
          _repeatMode = 'one';
        case AudioServiceRepeatMode.all:
        case AudioServiceRepeatMode.group:
          _repeatMode = 'all';
      }
      notifyListeners();
    });

    _mediaItemSub?.cancel();
    _mediaItemSub = _handler!.mediaItem.stream.listen((item) {
      if (item != null) {
        _title = item.title;
        _artist = item.artist ?? '';
        _artUri = item.artUri;
        _duration = item.duration ?? Duration.zero;
        _videoUrl = item.extras?['videoUrl'] as String?;
        _youtubeVideoId = item.extras?['youtubeVideoId'] as String?;
      }
      notifyListeners();
    });

    _queueSub?.cancel();
    _queueSub = _handler!.queue.stream.listen((items) {
      _queue = items;
      notifyListeners();
    });
  }

  /// Ensure the handler is ready before forwarding control calls.
  Future<bool> _ensureHandler() async {
    if (_handler != null) return true;
    if (!_initStarted) {
      await init();
    } else {
      try {
        _handler = await musicHandlerFuture
            .timeout(const Duration(seconds: 15));
      } catch (e) {
        debugPrint('[AUDIO] _ensureHandler failed: $e');
        _hasError = true;
        notifyListeners();
        return false;
      }
    }
    return _handler != null;
  }

  // ── Controls ──────────────────────────────────────────────────────────

  Future<void> play() async {
    if (!await _ensureHandler()) return;
    await _handler!.play();
  }

  Future<void> pause() async {
    if (!await _ensureHandler()) return;
    await _handler!.pause();
  }

  Future<void> togglePlayPause() async {
    if (!await _ensureHandler()) return;
    _handler!.togglePlayPause();
  }

  Future<void> skipToNext() async {
    if (!await _ensureHandler()) return;
    await _handler!.skipToNext();
  }

  Future<void> skipToPrevious() async {
    if (!await _ensureHandler()) return;
    await _handler!.skipToPrevious();
  }

  Future<void> seek(Duration pos) async {
    if (!await _ensureHandler()) return;
    await _handler!.seek(pos);
  }

  Future<void> toggleShuffle() async {
    if (!await _ensureHandler()) return;
    await _handler!.toggleShuffle();
  }

  Future<void> cycleRepeat() async {
    if (!await _ensureHandler()) return;
    await _handler!.cycleRepeat();
  }

  Future<void> setSpeed(double speed) async {
    _speed = speed;
    notifyListeners();
    if (!await _ensureHandler()) return;
    await _handler!.setSpeed(speed);
  }

  Future<void> setVolume(double volume) async {
    _volume = volume;
    notifyListeners();
    if (!await _ensureHandler()) return;
    await _handler!.setVolume(volume);
  }

  /// Load queue and start playback. Returns true on success.
  Future<bool> load(List<MediaItem> items,
      {int index = 0, bool autoPlay = true}) async {
    if (!await _ensureHandler()) return false;
    if (kDebugMode) {
      debugPrint('[NOTIFIER] load() — ${items.length} items, index=$index, autoPlay=$autoPlay');
      debugPrint('[NOTIFIER] load() — first item id=${items.first.id}, title=${items.first.title}');
    }
    try {
      await _handler!.load(items, index: index, autoPlay: autoPlay);
      _hasError = false;
      if (kDebugMode) debugPrint('[NOTIFIER] load() — SUCCESS, isPlaying=$_isPlaying');
      return true;
    } catch (e, stack) {
      _lastError = e.toString();
      if (kDebugMode) debugPrint('[NOTIFIER] ❌ load error: $_lastError');
      if (kDebugMode) debugPrint('[NOTIFIER] ❌ stack: $stack');
      _hasError = true;
      notifyListeners();
      return false;
    }
  }

  Future<bool> loadAndPlay(List<MediaItem> items, {int index = 0}) async {
    return load(items, index: index, autoPlay: true);
  }

  String formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _mediaItemSub?.cancel();
    _queueSub?.cancel();
    super.dispose();
  }
}
