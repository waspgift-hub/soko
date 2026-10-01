import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

/// One entry handed to the audio engine.
///
/// Deliberately separate from `ProfileMediaItem`: the handler must not know
/// about YouTube, seller queues or the video engine, and keeping the types
/// apart avoids a circular import with the controller.
class AudioTrack {
  final String id;
  final String title;
  final String artist;
  final String album;

  /// Network or file path, already resolved (never a YouTube page URL).
  final String url;
  final bool isLocalFile;
  final String? artworkUrl;
  final Duration? duration;

  const AudioTrack({
    required this.id,
    required this.title,
    this.artist = '',
    this.album = '',
    required this.url,
    this.isLocalFile = false,
    this.artworkUrl,
    this.duration,
  });

  MediaItem toMediaItem() => MediaItem(
        id: id,
        title: title,
        artist: artist.isEmpty ? null : artist,
        album: album.isEmpty ? null : album,
        duration: duration,
        artUri: artworkUrl != null && artworkUrl!.isNotEmpty
            ? Uri.tryParse(artworkUrl!)
            : null,
      );
}

/// Repeat behaviour understood by the handler, mirrored from the controller's
/// `QueueRepeatMode` so this file stays free of controller imports.
enum AudioRepeatMode { off, all, one }

/// Bridges just_audio to the OS media session.
///
/// Owns the single [AudioPlayer] that backs all audio playback. `audio_service`
/// uses it to publish the notification, lock-screen controls and background
/// playback; the controller subscribes to the streams below to keep its own UI
/// state in sync.
///
/// The singleton is created once and handed to `AudioService.init` from
/// `main.dart`. When the service cannot start — widget tests, unsupported
/// platforms, or a user who denied notifications — [isReady] stays false and
/// callers fall back to the `video_player` engine.
class MediaAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  MediaAudioHandler._();

  static final MediaAudioHandler instance = MediaAudioHandler._();

  // Created lazily in [activate] so merely touching the singleton (which the
  // controller does to check [isReady]) never spins up a platform player —
  // that keeps widget tests, which never activate the service, side-effect
  // free.
  AudioPlayer? _playerInstance;
  AudioPlayer get _player => _playerInstance!;
  bool _ready = false;

  /// True once `AudioService.init` has succeeded and the session is
  /// configured. Everything that routes audio must check this first.
  bool get isReady => _ready;

  /// Direct access for features that need a just_audio-only API (e.g. waveform
  /// or precise buffering). Prefer the controller for normal playback.
  AudioPlayer get player => _player;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;

  Duration get position => _position;
  Duration get duration => _duration;
  bool get playing => _playing;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration> get durationStream =>
      _player.durationStream.where((d) => d != null).cast<Duration>();
  Stream<bool> get playingStream => _player.playingStream;
  Stream<int> get indexStream =>
      _player.currentIndexStream.where((i) => i != null).cast<int>();

  /// Emits once whenever playback reaches the end of a track. The controller
  /// maps this onto `ProfileMediaState.completed`; advancing is handled by the
  /// player's loop mode, so listeners must not skip again.
  Stream<void> get completedStream => _player.processingStateStream
      .where((s) => s == ProcessingState.completed)
      .map((_) {});

  /// Emits the failing track's id when a load or decode fails.
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();
  Stream<String> get errorStream => _errorController.stream;

  int _sourceGeneration = 0;

  /// Called once by [initSokoMediaAudio] after `AudioService.init` resolves.
  Future<void> activate() async {
    if (_ready) return;
    _playerInstance = AudioPlayer();
    _ready = true;

    final session = await AudioSession.instance;
    // Music configuration: keeps audio alive when the screen locks and ducks
    // for turn-by-turn or calls instead of stopping.
    await session.configure(const AudioSessionConfiguration.music());

    _player.playbackEventStream.listen(
      _broadcastState,
      onError: (Object e, StackTrace st) {
        _errorController.add('playback');
      },
    );
    _player.durationStream.listen((d) {
      if (d != null) _duration = d;
    });
    _player.positionStream.listen((p) => _position = p);
    _player.playingStream.listen((p) => _playing = p);
    _player.currentIndexStream.listen((index) {
      if (index == null) return;
      final tag = _player.sequenceState?.currentSource?.tag;
      if (tag is MediaItem) mediaItem.add(tag);
      _broadcastState(_player.playbackEvent);
    });
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _broadcastState(_player.playbackEvent);
      }
    });

    _broadcastState(_player.playbackEvent);
  }

  void _broadcastState(PlaybackEvent event) {
    if (!_ready) return;
    final playing = _player.playing;
    final queueIndex = _player.currentIndex;
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 2],
        processingState: switch (_player.processingState) {
          ProcessingState.idle => AudioProcessingState.idle,
          ProcessingState.loading => AudioProcessingState.loading,
          ProcessingState.buffering => AudioProcessingState.buffering,
          ProcessingState.ready => AudioProcessingState.ready,
          ProcessingState.completed => AudioProcessingState.completed,
        },
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: queueIndex,
      ),
    );
  }

  /// Replaces the queue and starts [startIndex]. A monotonic generation guard
  /// drops a stale load if the user skipped to another track while the first
  /// was still resolving its source.
  Future<void> loadQueue(
    List<AudioTrack> tracks, {
    required int startIndex,
    required bool autoplay,
    required AudioRepeatMode repeatMode,
  }) async {
    if (!_ready) return;
    final generation = ++_sourceGeneration;
    final start = startIndex.clamp(0, tracks.isEmpty ? 0 : tracks.length - 1);

    await updateQueue([for (final t in tracks) t.toMediaItem()]);

    try {
      // just_audio 0.9 has no setAudioSources; the concatenating source is the
      // supported way to hand it a playlist with an initial index.
      await _player.setAudioSource(
        ConcatenatingAudioSource(
          children: [for (final t in tracks) _sourceFor(t)],
        ),
        initialIndex: start,
        initialPosition: Duration.zero,
        preload: true,
      );
    } catch (_) {
      if (generation == _sourceGeneration) {
        _errorController.add(tracks.isEmpty ? '' : tracks[start].id);
      }
      return;
    }
    if (generation != _sourceGeneration) return;

    await applyRepeatMode(repeatMode);
    final tag = _player.sequenceState?.currentSource?.tag;
    if (tag is MediaItem) mediaItem.add(tag);
    if (autoplay) {
      await _player.play();
    } else {
      await _player.pause();
    }
  }

  AudioSource _sourceFor(AudioTrack t) {
    final tag = t.toMediaItem();
    if (t.isLocalFile) return AudioSource.file(t.url, tag: tag);
    final parsed = Uri.tryParse(t.url);
    if (parsed != null && parsed.hasScheme) {
      return AudioSource.uri(parsed, tag: tag);
    }
    // A path without a scheme (some media-store entries) is a file on disk.
    return AudioSource.file(t.url, tag: tag);
  }

  /// Moves to a queue position without changing the repeat/autoplay state.
  Future<void> skipToIndex(int index, {bool autoplay = true}) async {
    if (!_ready) return;
    final length = _player.sequence?.length ?? 0;
    if (index < 0 || index >= length) return;
    await _player.seek(Duration.zero, index: index);
    if (autoplay && !_player.playing) await _player.play();
  }

  /// Applies the controller's repeat mode to the player. Named differently from
  /// the audio_service action below so the two intents stay separate: this one
  /// is Soko Vibe's queue mode, the override is the OS asking for a mode.
  Future<void> applyRepeatMode(AudioRepeatMode mode) async {
    if (!_ready) return;
    await _player.setLoopMode(
      switch (mode) {
        AudioRepeatMode.off => LoopMode.off,
        AudioRepeatMode.all => LoopMode.all,
        AudioRepeatMode.one => LoopMode.one,
      },
    );
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    await _player.setLoopMode(
      switch (repeatMode) {
        AudioServiceRepeatMode.none => LoopMode.off,
        AudioServiceRepeatMode.one => LoopMode.one,
        AudioServiceRepeatMode.all => LoopMode.all,
        AudioServiceRepeatMode.group => LoopMode.all,
      },
    );
  }

  /// Volume is not part of the audio_service contract, so this is a plain
  /// method the controller calls for mute.
  Future<void> setPlayerVolume(double volume) async {
    if (_ready) await _player.setVolume(volume);
  }

  @override
  Future<void> play() async {
    if (_ready) await _player.play();
  }

  @override
  Future<void> pause() async {
    if (_ready) await _player.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    if (_ready) await _player.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    if (_ready) await _player.seekToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    if (_ready) await _player.seekToPrevious();
  }

  @override
  Future<void> setSpeed(double speed) async {
    if (_ready) await _player.setSpeed(speed);
  }

  /// Pauses instead of tearing the engine down, so returning to the app
  /// resumes instantly. The queue is released by [release] on explicit stop.
  @override
  Future<void> onTaskRemoved() async {
    await pause();
  }

  /// Clears the media session. Used by `ProfileMediaSession.stop()`.
  Future<void> release() async {
    if (!_ready) return;
    _sourceGeneration++;
    await _player.stop();
    await updateQueue(const []);
    mediaItem.add(null);
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        MediaControl.play,
        MediaControl.skipToNext,
      ],
      androidCompactActionIndices: const [0, 1, 2],
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
  }

  Future<void> dispose() async {
    await _playerInstance?.dispose();
    await _errorController.close();
  }
}

/// Starts the media session. Safe to call once at app startup.
///
/// Failures are swallowed by design: playback must still work through the
/// `video_player` fallback on devices where the foreground service cannot
/// start, so a media-session failure must never block the app.
Future<void> initSokoMediaAudio() async {
  try {
    await AudioService.init(
      builder: () => MediaAudioHandler.instance,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.soko_vibe.music',
        androidNotificationChannelName: 'Soko Vibe Music',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
    await MediaAudioHandler.instance.activate();
  } catch (_) {
    // Intentionally ignored — see doc comment.
  }
}
