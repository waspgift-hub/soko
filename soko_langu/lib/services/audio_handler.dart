import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'audio_cache_service.dart';

// ---------------------------------------------------------------------------
// YouTube stream headers — required to bypass geo-blocking on audio-only URLs
// ---------------------------------------------------------------------------
const _kUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/120.0.0.0 Safari/537.36';

final Map<String, String> kAudioHeaders = {
  'User-Agent': _kUserAgent,
  'Referer': 'https://www.youtube.com/',
  'Origin': 'https://www.youtube.com',
};

// ---------------------------------------------------------------------------
// Handler lifecycle — a [Completer] lets other parts of the app await the
// handler without polling or fragile retry loops.
// ---------------------------------------------------------------------------
final Completer<MusicHandler> _handlerCompleter = Completer<MusicHandler>();

/// Returns the active [MusicHandler] once it has been initialized by
/// [AudioService.init]. The future never throws — the handler is guaranteed
/// to be available before any playback API is called by the UI layer because
/// [MusicStateNotifier._waitForHandler] awaits this same future.
Future<MusicHandler> get musicHandlerFuture => _handlerCompleter.future;

MusicHandler? _resolvedHandler;

/// Convenience accessor for callers that know the handler is ready.
/// Throws [StateError] if accessed before [bindMusicHandler] is called.
MusicHandler get musicHandler {
  if (_resolvedHandler == null) {
    throw StateError(
      'MusicHandler not initialized yet — await musicHandlerFuture instead.',
    );
  }
  return _resolvedHandler!;
}

void bindMusicHandler(MusicHandler handler) {
  if (!_handlerCompleter.isCompleted) {
    _handlerCompleter.complete(handler);
  }
  _resolvedHandler ??= handler;
}

// ---------------------------------------------------------------------------
// MusicHandler — single source of truth for audio playback
// ---------------------------------------------------------------------------
//
//  Requirement coverage:
//  ─────────────────────
//  1. Native lock-screen & notification controls — [BaseAudioHandler]
//     provides the Android/iOS native notification automatically. We emit
//     correct [PlaybackState] with controls, position, metadata, and artwork.
//  2. Dynamic metadata (Title, Artist, Duration, Artwork) — every
//     [MediaItem] carries these; [BaseAudioHandler.mediaItem] stream pushes
//     them to the platform notification binding.
//  3. Background execution — [AudioService.init] keeps the Dart isolate alive;
//     [MusicHandler] extends [BaseAudioHandler] which runs in the background
//     service process. Audio focus handled via [AudioSession].
//  4. Smooth timeline sync — position updates broadcast every ~200 ms via
//     just_audio's own position stream (no redundant timer).
//  5. Bluetooth / hardware media buttons — [AudioService] registers a
//     [MediaButtonReceiver] in the manifest which routes all media events
//     to this handler's overridden methods.
//
// ---------------------------------------------------------------------------

class MusicHandler extends BaseAudioHandler {
  final AudioPlayer _player = AudioPlayer();

  bool _hasError = false;
  bool _wasPlayingBeforeInterruption = false;
  bool _loading = false;

  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<SequenceState?>? _sequenceSub;
  StreamSubscription<Duration>? _positionSub;

  ConcatenatingAudioSource? _concatenatingSource;

  final Completer<void> _sessionReady = Completer<void>();

  MusicHandler() {
    _setupListeners();
    _initSession();
  }

  // ── Playback Control ──────────────────────────────────────────────────
  // These are the methods [AudioService] calls in response to notification
  // button taps, Bluetooth media keys, and lock-screen controls.

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
      debugPrint('[AUDIO] play error: $e');
    }
  }

  @override
  Future<void> pause() async {
    try {
      await _player.pause();
      _broadcastState();
    } catch (e) {
      debugPrint('[AUDIO] pause error: $e');
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
      _hasError = false;
      await super.stop();
    } catch (e) {
      debugPrint('[AUDIO] stop error: $e');
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

  /// Required for the seek-bar in the Android notification on API 26+.
  @override
  Future<void> fastForward() async {
    await seek(_player.position + const Duration(seconds: 10));
  }

  /// Required for the seek-bar in the Android notification on API 26+.
  @override
  Future<void> rewind() async {
    await seek(_player.position - const Duration(seconds: 10));
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    await _player.setShuffleModeEnabled(
        shuffleMode == AudioServiceShuffleMode.all);
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

  /// Called when the user swipes away the notification (or the OS kills it).
  @override
  Future<void> onTaskRemoved() async {
    await stop();
  }

  /// Handle headset / Bluetooth media button clicks.
  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    switch (button) {
      case MediaButton.media:
        togglePlayPause();
      case MediaButton.next:
        await skipToNext();
      case MediaButton.previous:
        await skipToPrevious();
    }
  }

  /// Prepare the handler before first play.
  @override
  Future<void> prepare() async {
    // No-op by default — metadata is pushed when a queue is loaded.
  }

  /// Prepare from a media ID (called by Android Auto / Assistant).
  @override
  Future<void> prepareFromMediaId(String mediaId,
      [Map<String, dynamic>? extras]) async {
    final idx = int.tryParse(mediaId);
    if (idx != null && idx >= 0 && idx < queue.value.length) {
      mediaItem.add(queue.value[idx]);
    }
  }

  void togglePlayPause() {
    if (_player.playerState.playing) {
      pause();
    } else {
      play();
    }
  }

  // ── Queue Management ──────────────────────────────────────────────────

  /// Replace the queue with [items] and optionally start playback.
  Future<void> load(List<MediaItem> items,
      {int index = 0, bool autoPlay = true}) async {
    if (items.isEmpty) return;
    _loading = true;

    // Always wait for session (handles both pending and errored completions)
    try {
      await _sessionReady.future.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      if (kDebugMode) debugPrint('[AUDIO] Session init timed out — continuing anyway');
    } catch (e) {
      if (kDebugMode) debugPrint('[AUDIO] Session init error: $e — continuing anyway');
    }

    try {
      if (kDebugMode) {
        final firstUrl = items.first.id;
        debugPrint('[AUDIO] load() — ${items.length} items, index=$index, autoPlay=$autoPlay');
        debugPrint('[AUDIO] load() — first url: $firstUrl');
        debugPrint('[AUDIO] load() — player state before stop: processingState=${_player.processingState}, playing=${_player.playing}');
        debugPrint('[AUDIO] load() — player volume: ${_player.volume}');
        debugPrint('[AUDIO] load() — sessionReady complete: ${_sessionReady.isCompleted}');
      }

      await _player.stop();
      if (kDebugMode) debugPrint('[AUDIO] load() — after stop: processingState=${_player.processingState}');

      await _player.setVolume(1.0);

      queue.value = items;

      _concatenatingSource = ConcatenatingAudioSource(
        children: items.map((m) => _toSource(m)).toList(),
      );
      if (kDebugMode) debugPrint('[AUDIO] load() — calling setAudioSource...');
      await _player.setAudioSource(_concatenatingSource!,
          initialIndex: index);
      if (kDebugMode) debugPrint('[AUDIO] load() — after setAudioSource: processingState=${_player.processingState}, duration=${_player.duration}');

      final safeIndex = index.clamp(0, items.length - 1);
      mediaItem.add(items[safeIndex]);
      _hasError = false;

      if (autoPlay) {
        if (kDebugMode) debugPrint('[AUDIO] load() — calling _player.play()...');
        await _player.play();
        if (kDebugMode) debugPrint('[AUDIO] load() — after play: playing=${_player.playing}, processingState=${_player.processingState}, position=${_player.position}');
      }
    } on PlayerException catch (e) {
      if (kDebugMode) debugPrint('[AUDIO] ❌ PlayerException: code=${e.code}, message=${e.message}');
      _hasError = true;
      await _player.stop();
      rethrow;
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('[AUDIO] ❌ PlatformException: code=${e.code}, message=${e.message}');
      _hasError = true;
      await _player.stop();
      rethrow;
    } catch (e, stack) {
      if (kDebugMode) debugPrint('[AUDIO] ❌ Load error: $e');
      if (kDebugMode) debugPrint('[AUDIO] ❌ Stack: $stack');
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

  // ── Shuffle / Repeat ──────────────────────────────────────────────────

  bool get isShuffled => _player.shuffleModeEnabled;

  Future<void> toggleShuffle() async {
    await _player.setShuffleModeEnabled(!_player.shuffleModeEnabled);
    _broadcastState();
  }

  LoopMode get repeatMode => _player.loopMode;

  LoopMode get nextRepeatMode {
    switch (_player.loopMode) {
      case LoopMode.off:
        return LoopMode.all;
      case LoopMode.all:
        return LoopMode.one;
      case LoopMode.one:
        return LoopMode.off;
    }
  }

  Future<void> cycleRepeat() async {
    await _player.setLoopMode(nextRepeatMode);
    _broadcastState();
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
    _broadcastState();
  }

  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume);
    _broadcastState();
  }

  // ── State Getters ─────────────────────────────────────────────────────

  bool get isPlaying => _player.playerState.playing;
  bool get hasError => _hasError;
  Duration get position => _player.position;
  Duration get duration => _player.duration ?? Duration.zero;
  int? get currentIndex => _player.currentIndex;
  SequenceState? get sequenceState => _player.sequenceState;
  List<MediaItem> get currentQueue => queue.value;
  double get speed => _player.speed;
  double get volume => _player.volume;
  bool get shuffleEnabled => _player.shuffleModeEnabled;
  LoopMode get loopMode => _player.loopMode;

  // ── Internal: Audio Session ───────────────────────────────────────────

  /// Configures the [AudioSession] for music playback with proper focus
  /// handling (ducking, interruption on phone calls).
  Future<void> _initSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.mixWithOthers,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        avAudioSessionRouteSharingPolicy:
            AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions:
            AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: false,
      ));
      _interruptionSub =
          session.interruptionEventStream.listen(_onInterruption);
      _sessionReady.complete();
    } catch (e) {
      debugPrint('[AUDIO] Session init failed: $e');
      _sessionReady.completeError(e);
    }
  }

  /// Handle audio focus changes — pause on incoming call, resume after.
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

  // ── Internal: Listeners ───────────────────────────────────────────────

  void _setupListeners() {
    // Playback event stream — emits state, position, and metadata changes.
    _player.playbackEventStream.listen((event) {
      try {
        _onPlaybackEvent(event);
      } catch (e) {
        debugPrint('playbackEvent error: $e');
      }
    });

    // Duration stream — fires when the duration is known.
    _player.durationStream.listen((_) {
      _hasError = false;
      _broadcastState();
    });

    // Sequence stream — fires when the queue changes or track advances.
    _sequenceSub = _player.sequenceStateStream.listen((state) {
      if (_loading) return;
      final tag = state?.currentSource?.tag;
      if (tag is MediaItem) mediaItem.add(tag);
      _broadcastState();
      if (state?.sequence.isEmpty == true || state == null) {
        stop();
      }
    });

    // Position stream — fires every ~200ms for smooth real-time progress
    _positionSub = _player.positionStream.listen((_) {
      _broadcastState();
    });
  }

  int _lastPlaybackSeq = -1;

  void _onPlaybackEvent(PlaybackEvent event) {
    final idx = event.currentIndex;
    final ps = event.processingState;

    if (kDebugMode) {
      final seq = event.updateTime.microsecondsSinceEpoch;
      if (_lastPlaybackSeq != seq) {
        _lastPlaybackSeq = seq;
        debugPrint('[AUDIO] event: ps=$ps, idx=$idx, playing=${_player.playing}');
      }
    }

    if (ps == ProcessingState.idle && idx == null && !_loading) {
      _hasError = true;
      debugPrint('[AUDIO] ⚠️ Player idle with no index — possible error');
    }

    if (ps == ProcessingState.ready || ps == ProcessingState.buffering) {
      _hasError = false;
    }

    if (idx != null && idx >= 0 && idx < queue.value.length) {
      mediaItem.add(queue.value[idx]);
    }

    _broadcastState();
  }

  // ── Internal: State Broadcasting ──────────────────────────────────────

  /// Emit a [PlaybackState] to [BaseAudioHandler.playbackState] which
  /// audio_service uses to update the native notification and lock screen.
  ///
  /// Controls map to Android 13+ system media control slots:
  ///   Slot 1 — play/pause (automatic from [playing] state)
  ///   Slot 2 — previous (or custom/empty)
  ///   Slot 3 — next (or custom/empty)
  ///   Slots 4-5 — overflow (fast-forward, rewind, custom buttons)
  /// The seek bar is enabled via [MediaAction.seek] in [systemActions].
  void _broadcastState() {
    try {
      final state = _player.playerState;
      final playing = state.playing;
      final hasMultiple = queue.value.length > 1;

      final controls = <MediaControl>[
        if (hasMultiple) MediaControl.skipToPrevious,
        playing ? MediaControl.pause : MediaControl.play,
        if (hasMultiple) MediaControl.skipToNext,
        MediaControl.fastForward,
        MediaControl.rewind,
        MediaControl.custom(
          androidIcon: 'drawable/ic_favorite',
          label: 'Favorite',
          name: 'toggle_favorite',
        ),
      ];

      playbackState.add(PlaybackState(
        controls: controls,
        androidCompactActionIndices: hasMultiple ? [0, 1, 2] : [0],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.setShuffleMode,
          MediaAction.setRepeatMode,
        },
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
    } catch (e) {
      debugPrint('[AUDIO] broadcastState error: $e');
    }
  }

  // ── Custom Actions ──────────────────────────────────────────────────
  // These are triggered by custom buttons in the system media controls
  // (e.g. a "favorite" button in Android 13+ overflow slots 4-5).

  @override
  Future<dynamic> customAction(String name,
      [Map<String, dynamic>? extras]) async {
    switch (name) {
      case 'toggle_favorite':
        // Forward to the UI layer so it can update its favorite state
        customEvent.add(<String, dynamic>{
          'action': 'toggle_favorite',
          'extras': extras,
        });
        return;
      default:
        return super.customAction(name, extras);
    }
  }

  // ── Media Resumption (Android 13+) ───────────────────────────────────
  // SystemUI queries the 'recent' root to populate the carousel with the
  // last-played item. Without this, the app won't appear in the carousel.

  @override
  Future<List<MediaItem>> getChildren(String parentMediaId,
      [Map<String, dynamic>? options]) async {
    if (parentMediaId == AudioService.recentRootId) {
      final current = mediaItem.value;
      if (current != null) return [current];
      return [];
    }
    return [];
  }

  AudioProcessingState _mapProcessingState(ProcessingState p) {
    switch (p) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  AudioServiceRepeatMode _mapRepeatMode(LoopMode mode) {
    switch (mode) {
      case LoopMode.off:
        return AudioServiceRepeatMode.none;
      case LoopMode.one:
        return AudioServiceRepeatMode.one;
      case LoopMode.all:
        return AudioServiceRepeatMode.all;
    }
  }

  /// Convert a [MediaItem] to an [AudioSource] for [just_audio].
  AudioSource _toSource(MediaItem item) {
    var url = item.id;
    final cached = AudioCacheService().tryGetCached(url);
    if (cached != null) url = cached;

    var uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      uri = Uri.file(url);
    }

    final host = uri.host.toLowerCase();
    final isStream = host.contains('googlevideo.com') ||
        host.contains('youtube.com') ||
        host.contains('ytimg.com') ||
        host.contains('ggpht.com');
    final headers = (uri.scheme == 'http' || uri.scheme == 'https') && isStream
        ? kAudioHeaders
        : null;

    debugPrint('[AUDIO] _toSource: url=$url, host=$host, scheme=${uri.scheme}, isStream=$isStream');
    return AudioSource.uri(uri, headers: headers, tag: item);
  }

  // ── Cleanup ───────────────────────────────────────────────────────────

  Future<void> dispose() async {
    await _interruptionSub?.cancel();
    await _sequenceSub?.cancel();
    await _positionSub?.cancel();
    await _player.dispose();
  }
}
