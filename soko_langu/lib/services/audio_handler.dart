import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'audio_cache_service.dart';







class SokoAudioHandler extends BaseAudioHandler with WidgetsBindingObserver {
  static SokoAudioHandler? _instance;
  factory SokoAudioHandler() {
    _instance ??= SokoAudioHandler._();
    return _instance!;
  }
  SokoAudioHandler._() {
    WidgetsBinding.instance.addObserver(this);
    // Set up listeners synchronously before async session init,
    // to avoid race where play() is called before listeners are attached.
    _setupPlayerListeners();
    _startPositionUpdates();
    _initAsync();
  }

  Future<void> _initAsync() async {
    try {
      await _setupSession();
    } catch (e) {
      debugPrint('SokoAudioHandler init error: $e');
    }
  }

  final AudioPlayer _player = AudioPlayer();
  bool _hasError = false;
  bool _wasPlayingBeforeInterruption = false;
  StreamSubscription<Duration?>? _positionSub;
  StreamSubscription<PlaybackEvent>? _playbackSub;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;

  Future<void> _setupSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(
        const AudioSessionConfiguration(
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
        ),
      );
      _interruptionSub = session.interruptionEventStream.listen((event) {
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
      });
    } catch (e) {
      debugPrint('AudioSession config failed: $e');
    }
  }

  void _setupPlayerListeners() {
    _playbackSub = _player.playbackEventStream.listen((event) {
      try {
        _onPlaybackEvent(event);
      } catch (e) {
        debugPrint('playbackEventStream error: $e');
      }
    });
    _stateSub = _player.playerStateStream.listen((state) {
      try {
        _safeBroadcastState();
      } catch (e) {
        debugPrint('playerStateStream error: $e');
      }
    });
    _durationSub = _player.durationStream.listen((_) {
      try {
        _hasError = false;
        _safeBroadcastState();
      } catch (_) {}
    });
  }

  void _startPositionUpdates() {
    try {
      _positionSub?.cancel();
      _positionSub = _player.positionStream.listen((_) {
        _safeBroadcastState();
      });
    } catch (_) {}
  }

  void _onPlaybackEvent(PlaybackEvent event) {
    try {
      final idx = event.currentIndex;

      if (event.processingState == ProcessingState.idle && idx == null) {
        _hasError = true;
      }

      // Propagate currently playing item's metadata to lock-screen/controls.
      // Use the player's currentIndex (idx) when available.
      if (idx != null && idx >= 0 && idx < queue.value.length) {
        mediaItem.add(queue.value[idx]);
      }

      _safeBroadcastState();
    } catch (e) {
      debugPrint('_onPlaybackEvent error: $e');
    }
  }


  void _safeBroadcastState() {
    try {
      final state = _player.playerState;
      final playing = state.playing;
      final pState = state.processingState;
      debugPrint('_safeBroadcastState: playing=$playing processingState=$pState queueLen=${queue.value.length}');
      final apState = _mapProcessingState(pState);
      final hasMultiple = queue.value.length > 1;

      final controls = <MediaControl>[
        if (hasMultiple) MediaControl.skipToPrevious,
        playing ? MediaControl.pause : MediaControl.play,
        if (hasMultiple) MediaControl.skipToNext,
      ];

      final compact = hasMultiple ? [0, 1, 2] : [0];

      playbackState.add(
        PlaybackState(
          controls: controls,
          androidCompactActionIndices: compact,
          systemActions: {MediaAction.seek},
          processingState: apState,
          playing: playing,
          bufferedPosition: _player.bufferedPosition,
          updatePosition: _player.position,
          speed: 1.0,
          queueIndex: _player.currentIndex ?? 0,
          repeatMode: _mapLoopToRepeatMode(_player.loopMode),
          shuffleMode: _player.shuffleModeEnabled
              ? AudioServiceShuffleMode.all
              : AudioServiceShuffleMode.none,
        ),
      );
    } catch (e) {
      debugPrint('_safeBroadcastState error: $e');
    }
  }

  AudioServiceRepeatMode _mapLoopToRepeatMode(LoopMode mode) {
    switch (mode) {
      case LoopMode.off: return AudioServiceRepeatMode.none;
      case LoopMode.one: return AudioServiceRepeatMode.one;
      case LoopMode.all: return AudioServiceRepeatMode.all;
    }
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}

  @override
  Future<void> play() async {
    debugPrint('play() called — processingState=${_player.processingState} currentIndex=${_player.currentIndex}');
    try {
      if (_player.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero);
      }
      if (_player.processingState == ProcessingState.idle && _player.currentIndex != null) {
        await _player.seek(Duration.zero, index: _player.currentIndex);
      }
      await _player.play();
      debugPrint('play() — after _player.play(), playing=${_player.playing}');
    } catch (e) {
      debugPrint('play error: $e');
    }
  }

  @override
  Future<void> pause() async {
    try {
      await _player.pause();
    } catch (e) {
      debugPrint('pause error: $e');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _player.stop();
      await _player.seek(Duration.zero);
      await AudioService.stop();
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
    _safeBroadcastState();
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    switch (repeatMode) {
      case AudioServiceRepeatMode.none: await _player.setLoopMode(LoopMode.off); break;
      case AudioServiceRepeatMode.one: await _player.setLoopMode(LoopMode.one); break;
      case AudioServiceRepeatMode.all: await _player.setLoopMode(LoopMode.all); break;
      case AudioServiceRepeatMode.group: await _player.setLoopMode(LoopMode.all); break;
    }
    _safeBroadcastState();
  }

  @override
  Future<void> onTaskRemoved() async {
    // Don't stop playback when app is swiped away from recents.
    // Keep playing so the notification remains controllable.
  }

  Future<void> load(List<MediaItem> items, {int initialIndex = 0}) async {
    if (items.isEmpty) return;
    debugPrint('load() called with ${items.length} items, initialIndex=$initialIndex');
    try {
      await _player.stop();
      await _player.seek(Duration.zero);

      queue.value = items;

      await _player.setAudioSource(
        ConcatenatingAudioSource(
          children: items
              .map((m) => AudioSource.uri(Uri.parse(m.id), tag: m))
              .toList(),
        ),
        initialIndex: initialIndex,
      );

      // Emit metadata for the initial item.
      final safeIndex = initialIndex.clamp(0, items.length - 1);
      mediaItem.add(items[safeIndex]);

      _hasError = false;
      _safeBroadcastState();
    } catch (e) {
      debugPrint('load error: $e');
    }
  }


  Future<void> loadFromUrls(
    List<String> urls, {
    String? title,
    String? artist,
    List<String>? titles,
    List<String>? artists,
    List<String>? imageUrls,
    int initialIndex = 0,
  }) async {
    final cache = AudioCacheService();
    final items = <MediaItem>[];

    for (var i = 0; i < urls.length; i++) {
      final url = urls[i];
      final cached = await cache.get(url);
      final playbackUri = cached ?? url;

      final img = (imageUrls != null && i < imageUrls.length)
          ? imageUrls[i]
          : null;

      items.add(
        MediaItem(
          // id must be a playable URI/path.
          id: playbackUri,
          // Metadata for lock screen.
          title: (titles != null && i < titles.length)
              ? titles[i]
              : (title ?? 'Audio'),
          artist: (artists != null && i < artists.length)
              ? artists[i]
              : (artist ?? ''),
          artUri: (img != null && img.isNotEmpty) ? Uri.parse(img) : null,
        ),
      );
    }

    await load(items, initialIndex: initialIndex);
  }


  bool get isShuffled => _player.shuffleModeEnabled;

  Future<void> toggleShuffle() async {
    try {
      await _player.setShuffleModeEnabled(!_player.shuffleModeEnabled);
      _safeBroadcastState();
    } catch (_) {}
  }

  LoopMode get repeatMode => _player.loopMode;

  Future<void> cycleRepeat() async {
    try {
      switch (_player.loopMode) {
        case LoopMode.off:
          await _player.setLoopMode(LoopMode.all);
        case LoopMode.all:
          await _player.setLoopMode(LoopMode.one);
        case LoopMode.one:
          await _player.setLoopMode(LoopMode.off);
      }
      _safeBroadcastState();
    } catch (_) {}
  }

  Future<void> togglePlayPause() async {
    try {
      if (_player.playerState.playing) {
        await pause();
      } else {
        await play();
      }
    } catch (_) {}
  }

  bool get isPlaying => _player.playerState.playing;

  bool get hasError => _hasError;

  Duration get duration => _player.duration ?? Duration.zero;

  SequenceState? get sequenceState => _player.sequenceState;

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    _playbackSub?.cancel();
    _stateSub?.cancel();
    _durationSub?.cancel();
    _positionSub?.cancel();
    _interruptionSub?.cancel();
    await _player.dispose();
    _instance = null;
  }
}
