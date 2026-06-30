import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import '../services/audio_handler.dart';

/// Provides reactive music playback state to the UI layer.
/// Single source of truth for all widgets (mini-player, full player, queue).
class MusicStateNotifier extends ChangeNotifier {
  MusicHandler? _handler;
  final Completer<void> _handlerReady = Completer<void>();
  StreamSubscription<PlaybackState>? _stateSub;
  StreamSubscription<MediaItem?>? _mediaItemSub;
  StreamSubscription<List<MediaItem>>? _queueSub;

  String _title = '';
  String _artist = '';
  Uri? _artUri;
  bool _isPlaying = false;
  bool _hasActivePlayback = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  List<MediaItem> _queue = [];
  bool _hasError = false;

  String get title => _title;
  String get artist => _artist;
  Uri? get artUri => _artUri;
  bool get isPlaying => _isPlaying;
  bool get hasActivePlayback => _hasActivePlayback;
  Duration get position => _position;
  Duration get duration => _duration;
  List<MediaItem> get queue => _queue;
  int get queueLength => _queue.length;
  bool get hasError => _hasError;
  int? get currentIndex => _handler?.currentIndex;

  double get progress {
    if (_duration.inMilliseconds <= 0) return 0.0;
    return (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);
  }

  /// Whether the audio handler has been initialized and is ready.
  bool get isHandlerReady => _handlerReady.isCompleted;

  /// Waits for the handler to become available (with timeout).
  Future<bool> _waitForHandler() async {
    if (_handlerReady.isCompleted) return true;
    try {
      await _handlerReady.future.timeout(const Duration(seconds: 10));
      return true;
    } on TimeoutException {
      _hasError = true;
      notifyListeners();
      return false;
    }
  }

  /// Call once after AudioService.init completes.
  void init() {
    try {
      _handler = musicHandler;
      _handlerReady.complete();
    } catch (_) {
      Future.delayed(const Duration(milliseconds: 500), init);
      return;
    }

    _stateSub?.cancel();
    _stateSub = _handler!.playbackState.stream.listen((state) {
      _isPlaying = state.playing;
      _position = state.position;
      _hasActivePlayback =
          state.processingState != AudioProcessingState.idle &&
          state.processingState != AudioProcessingState.completed;
      notifyListeners();
    });

    _mediaItemSub?.cancel();
    _mediaItemSub = _handler!.mediaItem.stream.listen((item) {
      if (item != null) {
        _title = item.title;
        _artist = item.artist ?? '';
        _artUri = item.artUri;
      }
      notifyListeners();
    });

    _queueSub?.cancel();
    _queueSub = _handler!.queue.stream.listen((items) {
      _queue = items;
      notifyListeners();
    });
  }

  // ── Controls ────────────────────────────────────────────────

  Future<void> play() async {
    if (!await _waitForHandler()) return;
    await _handler!.play();
  }

  Future<void> pause() async {
    if (!await _waitForHandler()) return;
    await _handler!.pause();
  }

  Future<void> togglePlayPause() async {
    if (!await _waitForHandler()) return;
    _handler!.togglePlayPause();
  }

  Future<void> skipToNext() async {
    if (!await _waitForHandler()) return;
    await _handler!.skipToNext();
  }

  Future<void> skipToPrevious() async {
    if (!await _waitForHandler()) return;
    await _handler!.skipToPrevious();
  }

  Future<void> seek(Duration pos) async {
    if (!await _waitForHandler()) return;
    await _handler!.seek(pos);
  }

  Future<void> toggleShuffle() async {
    if (!await _waitForHandler()) return;
    await _handler!.toggleShuffle();
  }

  Future<void> cycleRepeat() async {
    if (!await _waitForHandler()) return;
    await _handler!.cycleRepeat();
  }

  /// Load queue and start playback. Returns true on success.
  Future<bool> load(List<MediaItem> items, {int index = 0, bool autoPlay = true}) async {
    if (!await _waitForHandler()) return false;
    try {
      await _handler!.load(items, index: index, autoPlay: autoPlay);
      _hasError = false;
      return true;
    } catch (e) {
      debugPrint('MusicStateNotifier.load error: $e');
      _hasError = true;
      notifyListeners();
      return false;
    }
  }

  /// Convenience — load and auto-play.
  Future<bool> loadAndPlay(List<MediaItem> items, {int index = 0}) async {
    return load(items, index: index, autoPlay: true);
  }

  String formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
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
