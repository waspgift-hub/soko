import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'audio_cache_service.dart';

/// Browser headers for YouTube streaming.
const _kUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/120.0.0.0 Safari/537.36';

final Map<String, String> kAudioHeaders = {
  'User-Agent': _kUserAgent,
  'Referer': 'https://www.youtube.com/',
  'Origin': 'https://www.youtube.com',
};

/// Global handler reference — set once by [bindMusicHandler].
MusicHandler? _globalHandler;

void bindMusicHandler(MusicHandler handler) {
  _globalHandler = handler;
}

/// Backward-compat for old screens.
MusicHandler get sokoAudio => musicHandler;

/// Access the active [MusicHandler] from anywhere in the app.
MusicHandler get musicHandler {
  final h = _globalHandler;
  if (h == null) {
    throw StateError('MusicHandler not initialized');
  }
  return h;
}

/// Core audio handler — single source of truth for all playback.
/// Manages just_audio, audio_session, and audio_service integration.
class MusicHandler extends BaseAudioHandler {
  final AudioPlayer _player = AudioPlayer();

  bool _hasError = false;
  bool _wasPlayingBeforeInterruption = false;
  bool _loading = false;

  StreamSubscription<Duration?>? _positionSub;
  StreamSubscription<PlaybackEvent>? _playbackSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<SequenceState?>? _sequenceSub;

  ConcatenatingAudioSource? _concatenatingSource;

  MusicHandler() {
    _initSession();
    _setupListeners();
    _startPositionUpdates();
  }

  // ── Playback Control ────────────────────────────────────────

  @override
  Future<void> play() async {
    try {
      if (_player.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero);
      }
      if (_player.processingState == ProcessingState.idle &&
          _player.currentIndex != null) {
        await _player.seek(Duration.zero, index: _player.currentIndex);
      }
      await _player.play();
      _broadcastState();
    } catch (e) {
      debugPrint('play error: $e');
    }
  }

  @override
  Future<void> pause() async {
    try {
      await _player.pause();
      _broadcastState();
    } catch (e) {
      debugPrint('pause error: $e');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _player.stop();
      await _player.seek(Duration.zero);
      queue.value = [];
      mediaItem.add(null);
      _concatenatingSource = null;
      await super.stop();
    } catch (e) {
      debugPrint('stop error: $e');
    }
  }

  @override
  Future<void> skipToNext() async {
    try {
      await _player.seekToNext();
    } catch (_) {}
  }

  @override
  Future<void> skipToPrevious() async {
    try {
      await _player.seekToPrevious();
    } catch (_) {}
  }

  @override
  Future<void> seek(Duration position) async {
    try {
      await _player.seek(position);
    } catch (_) {}
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    await _player.setShuffleModeEnabled(shuffleMode == AudioServiceShuffleMode.all);
    _broadcastState();
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    switch (repeatMode) {
      case AudioServiceRepeatMode.none:
        await _player.setLoopMode(LoopMode.off);
      case AudioServiceRepeatMode.one:
        await _player.setLoopMode(LoopMode.one);
      case AudioServiceRepeatMode.all:
      case AudioServiceRepeatMode.group:
        await _player.setLoopMode(LoopMode.all);
    }
    _broadcastState();
  }

  @override
  Future<void> onTaskRemoved() async {
    await stop();
  }

  void togglePlayPause() {
    if (_player.playerState.playing) {
      pause();
    } else {
      play();
    }
  }

  // ── Queue Management ────────────────────────────────────────

  /// Replace queue with [items] and optionally start playback.
  Future<void> load(List<MediaItem> items, {int index = 0, bool autoPlay = true}) async {
    if (items.isEmpty) return;
    _loading = true;
    try {
      await _player.stop();
      queue.value = items;

      _concatenatingSource = ConcatenatingAudioSource(
        children: items.map((m) => _toSource(m)).toList(),
      );
      await _player.setAudioSource(_concatenatingSource!, initialIndex: index);

      final safeIndex = index.clamp(0, items.length - 1);
      mediaItem.add(items[safeIndex]);
      _hasError = false;

      if (autoPlay) await _player.play();
    } on PlayerException catch (e) {
      debugPrint('load error: $e');
      _hasError = true;
      _player.stop();
      rethrow;
    } catch (e) {
      debugPrint('load error: $e');
      _hasError = true;
      rethrow;
    } finally {
      _loading = false;
      _broadcastState();
    }
  }

  /// Append a single item to the end of the queue.
  Future<void> addToQueue(MediaItem item) async {
    final src = _concatenatingSource;
    if (src == null) return;
    await src.add(_toSource(item));
    queue.value = [...queue.value, item];
  }

  /// Remove item at [index] from the queue.
  Future<void> removeFromQueue(int index) async {
    final src = _concatenatingSource;
    if (src == null || index < 0 || index >= queue.value.length) return;
    await src.removeAt(index);
    final items = [...queue.value];
    items.removeAt(index);
    queue.value = items;
  }

  // ── Shuffle / Repeat ────────────────────────────────────────

  bool get isShuffled => _player.shuffleModeEnabled;

  Future<void> toggleShuffle() async {
    await _player.setShuffleModeEnabled(!_player.shuffleModeEnabled);
    _broadcastState();
  }

  LoopMode get repeatMode => _player.loopMode;

  LoopMode get nextRepeatMode {
    switch (_player.loopMode) {
      case LoopMode.off: return LoopMode.all;
      case LoopMode.all: return LoopMode.one;
      case LoopMode.one: return LoopMode.off;
    }
  }

  Future<void> cycleRepeat() async {
    await _player.setLoopMode(nextRepeatMode);
    _broadcastState();
  }

  // ── State Getters ───────────────────────────────────────────

  bool get isPlaying => _player.playerState.playing;
  bool get hasError => _hasError;
  Duration get position => _player.position;
  Duration get duration => _player.duration ?? Duration.zero;
  int? get currentIndex => _player.currentIndex;
  SequenceState? get sequenceState => _player.sequenceState;
  List<MediaItem> get currentQueue => queue.value;

  // ── Internal: Session Setup ─────────────────────────────────

  Future<void> _initSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        avAudioSessionRouteSharingPolicy: AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: false,
      ));
      _interruptionSub = session.interruptionEventStream.listen(_onInterruption);
    } catch (e) {
      debugPrint('AudioSession error: $e');
    }
  }

  void _onInterruption(AudioInterruptionEvent event) {
    if (event.type == AudioInterruptionType.unknown) {
      _player.pause();
    } else if (event.begin) {
      if (event.type == AudioInterruptionType.pause) {
        _wasPlayingBeforeInterruption = _player.playing;
        _player.pause();
      }
    } else if (_wasPlayingBeforeInterruption) {
      _wasPlayingBeforeInterruption = false;
      _player.play();
    }
  }

  // ── Internal: Listeners ─────────────────────────────────────

  void _setupListeners() {
    _playbackSub = _player.playbackEventStream.listen((event) {
      try {
        _onPlaybackEvent(event);
      } catch (e) {
        debugPrint('playbackEvent error: $e');
      }
    });
    _durationSub = _player.durationStream.listen((_) {
      _hasError = false;
      _broadcastState();
    });
    _sequenceSub = _player.sequenceStateStream.listen((state) {
      if (_loading) return;
      final tag = state?.currentSource?.tag;
      if (tag is MediaItem) mediaItem.add(tag);
      _broadcastState();
      if (state?.sequence.isEmpty == true || state == null) {
        stop();
      }
    });
  }

  void _onPlaybackEvent(PlaybackEvent event) {
    final idx = event.currentIndex;
    if (event.processingState == ProcessingState.idle && idx == null) {
      _hasError = true;
    }
    if (idx != null && idx >= 0 && idx < queue.value.length) {
      mediaItem.add(queue.value[idx]);
    }
    _broadcastState();
  }

  DateTime _lastPositionUpdate = DateTime.now();

  void _startPositionUpdates() {
    _positionSub?.cancel();
    _positionSub = _player.positionStream.listen((_) {
      final now = DateTime.now();
      if (now.difference(_lastPositionUpdate) >= const Duration(milliseconds: 200)) {
        _lastPositionUpdate = now;
        _broadcastState();
      }
    });
  }

  // ── Internal: State Broadcasting ────────────────────────────

  void _broadcastState() {
    try {
      final state = _player.playerState;
      final playing = state.playing;
      final hasMultiple = queue.value.length > 1;

      playbackState.add(PlaybackState(
        controls: [
          if (hasMultiple) MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          if (hasMultiple) MediaControl.skipToNext,
          MediaControl.stop,
        ],
        androidCompactActionIndices: hasMultiple ? [0, 1, 2] : [0],
        systemActions: const {MediaAction.seek},
        processingState: _mapProcessingState(state.processingState),
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _player.currentIndex ?? 0,
        repeatMode: _mapRepeatMode(_player.loopMode),
        shuffleMode: _player.shuffleModeEnabled
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
      ));
    } catch (_) {}
  }

  AudioProcessingState _mapProcessingState(ProcessingState p) {
    switch (p) {
      case ProcessingState.idle: return AudioProcessingState.idle;
      case ProcessingState.loading: return AudioProcessingState.loading;
      case ProcessingState.buffering: return AudioProcessingState.buffering;
      case ProcessingState.ready: return AudioProcessingState.ready;
      case ProcessingState.completed: return AudioProcessingState.completed;
    }
  }

  AudioServiceRepeatMode _mapRepeatMode(LoopMode mode) {
    switch (mode) {
      case LoopMode.off: return AudioServiceRepeatMode.none;
      case LoopMode.one: return AudioServiceRepeatMode.one;
      case LoopMode.all: return AudioServiceRepeatMode.all;
    }
  }

  AudioSource _toSource(MediaItem item) {
    var url = item.id;
    final cached = AudioCacheService().tryGetCached(url);
    if (cached != null) url = cached;

    var uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      uri = Uri.file(url);
    }
    final headers = (uri.scheme == 'http' || uri.scheme == 'https')
        ? kAudioHeaders
        : null;
    return AudioSource.uri(uri, headers: headers, tag: item);
  }

  // ── Cleanup ─────────────────────────────────────────────────

  Future<void> dispose() async {
    _playbackSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _interruptionSub?.cancel();
    _sequenceSub?.cancel();
    await _player.dispose();
    _globalHandler = null;
  }
}
