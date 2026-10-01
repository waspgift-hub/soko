import 'dart:async';
import 'dart:io' show File;

import 'package:video_player/video_player.dart';

import 'media_audio_handler.dart';
import 'media_utils.dart';
import 'youtube_utils.dart';

/// One playable entry in the profile media queue.
class ProfileMediaItem {
  final String id;
  final String title;
  final String videoUrl;
  final String? thumbnailUrl;

  /// Absolute device path for songs stored on the phone. When set, playback
  /// reads the file directly — no network involved.
  final String? localPath;

  /// ID3 metadata, when the source has it. Used for the media notification and
  /// lock-screen controls; empty values are left out of the [MediaItem].
  final String artist;
  final String album;

  /// Known length, when the source exposes it up front. Lets the notification
  /// render a seek bar before the player has loaded the file.
  final Duration? duration;

  const ProfileMediaItem({
    required this.id,
    required this.title,
    required this.videoUrl,
    this.thumbnailUrl,
    this.localPath,
    this.artist = '',
    this.album = '',
    this.duration,
  });

  bool get isLocalFile => localPath != null && localPath!.isNotEmpty;

  /// True when the URL is a YouTube link. Those play through the embedded
  /// YouTube player (WebView) instead of the video_player engine, because
  /// YouTube never serves directly playable mp4 URLs.
  bool get isYouTube => !isLocalFile && isYouTubeUrl(videoUrl);

  /// True for audio files (mp3, m4a, ...). When the whole queue is audio it
  /// plays through just_audio so it can keep playing in the background; a
  /// mixed or broken setup falls back to the video engine.
  bool get isAudio =>
      !isYouTube &&
      (isAudioUrl(videoUrl) ||
          (isLocalFile && isAudioUrl(localPath!)));
}

/// Playback states exposed to the UI. Mirrors the handler-state idea Namida
/// uses (single source of truth outside the widget tree) so the featured
/// player and the up-next list never disagree about what is playing.
enum ProfileMediaState { idle, loading, playing, paused, completed, error }

/// Queue repeat behaviour, same three modes Namida offers.
enum QueueRepeatMode { off, all, one }

/// Which engine currently owns playback. Audio and video have separate owners
/// (just_audio vs video_player) and every transport call must dispatch to the
/// right one, hence an explicit flag rather than guessing from [current].
enum _MediaEngine { none, video, audio }

/// Queue + playback controller for the profile media section.
///
/// Audio-only queues play through [MediaAudioHandler] (just_audio +
/// audio_service) so playback survives the app going to the background and
/// surfaces in the notification and lock screen. Video and YouTube items — and
/// audio on a device where the media session could not start — use the
/// original [VideoPlayerController] path. Both engines feed the same streams,
/// so widgets never need to know which one is active.
class ProfileMediaController {
  List<ProfileMediaItem> _queue = const [];
  int _index = 0;
  VideoPlayerController? _video;
  bool _muted = false;
  bool _disposed = false;
  bool _completionFired = false;
  String? _error;

  _MediaEngine _engine = _MediaEngine.none;
  ProfileMediaState _currentState = ProfileMediaState.idle;

  /// Audio-engine mirrors of the streams, kept locally so seekBy and the
  /// toggle button can read them synchronously.
  bool _audioPlaying = false;
  Duration _audioPosition = Duration.zero;
  Duration _audioDuration = Duration.zero;
  bool _audioAttached = false;
  String? _loadedAudioSignature;
  final List<StreamSubscription<Object?>> _audioSubs = [];

  /// Playback speeds offered by the speed chip. Same steps Namida exposes in
  /// its player speed selector (settings.player.speeds).
  static const List<double> speeds = [1.0, 1.25, 1.5, 2.0];
  double _speed = 1.0;

  final _state = StreamController<ProfileMediaState>.broadcast();
  final _indexStream = StreamController<int>.broadcast();
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _mutedStream = StreamController<bool>.broadcast();
  final _speedStream = StreamController<double>.broadcast();
  final _repeatStream = StreamController<QueueRepeatMode>.broadcast();
  final _sleepStream = StreamController<Duration?>.broadcast();

  Stream<ProfileMediaState> get stateStream => _state.stream;
  Stream<int> get indexStream => _indexStream.stream;
  Stream<Duration> get positionStream => _position.stream;
  Stream<Duration> get durationStream => _duration.stream;
  Stream<bool> get mutedStream => _mutedStream.stream;
  Stream<double> get speedStream => _speedStream.stream;
  Stream<QueueRepeatMode> get repeatStream => _repeatStream.stream;
  Stream<Duration?> get sleepStream => _sleepStream.stream;

  List<ProfileMediaItem> get queue => List.unmodifiable(_queue);
  int get index => _index;
  ProfileMediaItem? get current => _queue.isEmpty ? null : _queue[_index];
  bool get muted => _muted;
  double get speed => _speed;
  QueueRepeatMode get repeatMode => _repeatMode;
  Duration? get sleepRemaining =>
      _sleepEndsAt?.difference(DateTime.now());
  bool get isCurrentYouTube => current?.isYouTube ?? false;
  bool get isCurrentAudio => current?.isAudio ?? false;

  /// True when playback is owned by just_audio. Full-screen UI branches on
  /// this to show the audio player instead of the video inline player.
  bool get isAudioEngine => _engine == _MediaEngine.audio;

  /// Single playback signal for the UI, valid on both engines. Widgets use it
  /// instead of peeking at `video?.value`, which is null for audio.
  bool get isPlaying => _currentState == ProfileMediaState.playing;

  /// Current playback position, valid on both engines. Lets a widget read the
  /// position synchronously (e.g. to sync lyrics) without waiting for a tick.
  Duration get position => _engine == _MediaEngine.audio
      ? _audioPosition
      : (_video?.value.position ?? Duration.zero);
  String? get error => _error;
  VideoPlayerController? get video => _video;

  QueueRepeatMode _repeatMode = QueueRepeatMode.all;
  DateTime? _sleepEndsAt;
  Timer? _sleepTimer;
  Timer? _sleepTicker;

  /// Next queue position with wrap-around (repeat-all, Namida default).
  static int nextIndex(int current, int length) =>
      length <= 0 ? 0 : (current + 1) % length;

  /// Previous queue position with wrap-around.
  static int previousIndex(int current, int length) =>
      length <= 0 ? 0 : (current - 1 + length) % length;

  /// Next queue position honouring the repeat mode. Pure so the repeat
  /// contract is unit-tested without a player: `one` pins the current item,
  /// `off` stops at the queue end, `all` wraps around.
  static int nextIndexForMode(int current, int length, QueueRepeatMode mode) {
    if (length <= 0) return 0;
    final at = current.clamp(0, length - 1);
    if (mode == QueueRepeatMode.one) return at;
    if (mode == QueueRepeatMode.off) return at >= length - 1 ? at : at + 1;
    return (at + 1) % length;
  }

  /// Replaces the queue. Keeps the current item when it survives the refresh
  /// so a background product-list update never restarts playback.
  Future<void> setQueue(List<ProfileMediaItem> items, {int startAt = 0}) async {
    final keepId = current?.id;
    final wasPlaying = isPlaying;
    _queue = List.unmodifiable(items);
    _loadedAudioSignature = null;
    if (_queue.isEmpty) {
      if (_engine == _MediaEngine.audio) {
        await MediaAudioHandler.instance.release();
        _engine = _MediaEngine.none;
      }
      await _teardownVideo();
      _index = 0;
      _emitAll(ProfileMediaState.idle, Duration.zero, Duration.zero);
      return;
    }
    var at = startAt.clamp(0, _queue.length - 1);
    if (keepId != null) {
      final kept = _queue.indexWhere((e) => e.id == keepId);
      if (kept != -1) at = kept;
    }
    await playAt(at, autoplay: wasPlaying);
  }

  Future<void> playAt(int i, {bool autoplay = true}) async {
    if (_queue.isEmpty || _disposed) return;
    final wasAudio = _engine == _MediaEngine.audio;
    _index = i.clamp(0, _queue.length - 1);
    _indexStream.add(_index);
    _completionFired = false;
    _error = null;
    final item = _queue[_index];

    if (_useAudioEngine) {
      _attachAudio();
      await _teardownVideo();
      _engine = _MediaEngine.audio;
      _audioPosition = Duration.zero;
      _audioDuration = item.duration ?? Duration.zero;
      _emitAll(ProfileMediaState.loading, Duration.zero, _audioDuration);
      final handler = MediaAudioHandler.instance;
      final signature = _audioSignature();
      if (signature != _loadedAudioSignature) {
        _loadedAudioSignature = signature;
        await handler.loadQueue(
          _queue.map(_toAudioTrack).toList(growable: false),
          startIndex: _index,
          autoplay: autoplay,
          repeatMode: _audioRepeatMode,
        );
      } else {
        await handler.skipToIndex(_index, autoplay: autoplay);
      }
      return;
    }

    if (wasAudio) {
      // Leaving audio for a video item: stop the background player so both
      // engines never sound at once.
      await MediaAudioHandler.instance.pause();
    }
    _engine = _MediaEngine.video;
    await _teardownVideo();
    if (item.isYouTube) {
      // YouTube items render the nocookie embed in a WebView — there is no
      // video_player engine to drive, so position ticks and completion
      // callbacks don't exist for them. Queue navigation still works.
      _emitAll(ProfileMediaState.playing, Duration.zero, Duration.zero);
      return;
    }
    _emitAll(ProfileMediaState.loading, Duration.zero, Duration.zero);
    final VideoPlayerController controller;
    if (item.isLocalFile) {
      controller = VideoPlayerController.file(File(item.localPath!));
    } else {
      controller = VideoPlayerController.networkUrl(Uri.parse(item.videoUrl));
    }
    _video = controller;
    controller.addListener(_onTick);
    try {
      await controller.initialize();
      if (_disposed || _video != controller) {
        await controller.dispose();
        return;
      }
      await controller.setVolume(_muted ? 0 : 1);
      await controller.setPlaybackSpeed(_speed);
      _duration.add(controller.value.duration);
      if (autoplay) {
        await controller.play();
        _state.add(ProfileMediaState.playing);
      } else {
        _state.add(ProfileMediaState.paused);
      }
    } catch (_) {
      if (_video == controller) {
        _error = item.title;
        _state.add(ProfileMediaState.error);
      }
      await controller.dispose();
    }
  }

  Future<void> play() async {
    if (_engine == _MediaEngine.audio) {
      await MediaAudioHandler.instance.play();
      return;
    }
    final c = _video;
    if (c == null) {
      if (_queue.isEmpty) return;
      if (current?.isYouTube == true) {
        if (!_disposed) _state.add(ProfileMediaState.playing);
        return;
      }
      await playAt(_index);
      return;
    }
    await c.play();
    _state.add(ProfileMediaState.playing);
  }

  Future<void> pause() async {
    if (_engine == _MediaEngine.audio) {
      await MediaAudioHandler.instance.pause();
      return;
    }
    await _video?.pause();
    if (!_disposed) _state.add(ProfileMediaState.paused);
  }

  Future<void> toggle() async {
    if (_engine == _MediaEngine.audio) {
      if (_audioPlaying) {
        await pause();
      } else {
        await play();
      }
      return;
    }
    if (_video?.value.isPlaying == true) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> next() =>
      playAt(nextIndexForMode(_index, _queue.length, _repeatMode));

  Future<void> previous() => playAt(previousIndex(_index, _queue.length));

  Future<void> seekTo(Duration position) async {
    if (_engine == _MediaEngine.audio) {
      await MediaAudioHandler.instance.seek(position);
      return;
    }
    await _video?.seekTo(position);
  }

  /// Relative seek that never leaves [0, duration]. Used by the double-tap
  /// zones so a -10s tap at 0:03 lands on 0:00 instead of throwing.
  Future<void> seekBy(Duration delta) async {
    if (_engine == _MediaEngine.audio) {
      await MediaAudioHandler.instance
          .seek(clampSeek(_audioPosition, delta, _audioDuration));
      return;
    }
    final c = _video;
    if (c == null || !c.value.isInitialized) return;
    await c.seekTo(clampSeek(c.value.position, delta, c.value.duration));
  }

  /// Pure clamp for relative seeks — unit-tested, no player required.
  static Duration clampSeek(Duration current, Duration delta, Duration duration) {
    final target = current + delta;
    if (target <= Duration.zero) return Duration.zero;
    if (duration > Duration.zero && target >= duration) return duration;
    return target;
  }

  Future<void> setSpeed(double speed) async {
    _speed = speed;
    if (_engine == _MediaEngine.audio) {
      await MediaAudioHandler.instance.setSpeed(speed);
    } else {
      await _video?.setPlaybackSpeed(speed);
    }
    if (!_disposed) _speedStream.add(speed);
  }

  Future<void> cycleSpeed() async {
    final i = speeds.indexOf(_speed);
    await setSpeed(speeds[(i + 1) % speeds.length]);
  }

  Future<void> cycleQueueRepeatMode() async {
    const order = [QueueRepeatMode.all, QueueRepeatMode.one, QueueRepeatMode.off];
    _repeatMode = order[(order.indexOf(_repeatMode) + 1) % order.length];
    if (_engine == _MediaEngine.audio) {
      await MediaAudioHandler.instance.applyRepeatMode(_audioRepeatMode);
    }
    if (!_disposed) _repeatStream.add(_repeatMode);
  }

  /// Sleep timer (Namida parity): pauses playback after [duration]. Emits the
  /// remaining time so the UI can show a countdown badge; emits null when the
  /// timer is cancelled or fires.
  void setSleepTimer(Duration duration) {
    cancelSleepTimer();
    _sleepEndsAt = DateTime.now().add(duration);
    _sleepStream.add(duration);
    _sleepTicker =
        Timer.periodic(const Duration(seconds: 5), (_) {
      if (_disposed) return;
      final remaining = sleepRemaining;
      if (remaining == null || remaining <= Duration.zero) return;
      _sleepStream.add(remaining);
    });
    _sleepTimer = Timer(duration, () async {
      _sleepEndsAt = null;
      _sleepTicker?.cancel();
      _sleepTicker = null;
      if (!_disposed) _sleepStream.add(null);
      await pause();
    });
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTicker?.cancel();
    _sleepTicker = null;
    if (_sleepEndsAt != null) {
      _sleepEndsAt = null;
      if (!_disposed) _sleepStream.add(null);
    }
  }

  Future<void> toggleMute() async {
    _muted = !_muted;
    if (_engine == _MediaEngine.audio) {
      await MediaAudioHandler.instance.setPlayerVolume(_muted ? 0 : 1);
    } else {
      await _video?.setVolume(_muted ? 0 : 1);
    }
    if (!_disposed) _mutedStream.add(_muted);
  }

  void _onTick() {
    if (_disposed) return;
    final c = _video;
    if (c == null || !c.value.isInitialized) return;
    _position.add(c.value.position);
    final d = c.value.duration;
    if (d > Duration.zero &&
        c.value.position >= d &&
        !c.value.isPlaying &&
        !_completionFired) {
      _completionFired = true;
      if (_repeatMode == QueueRepeatMode.one) {
        _state.add(ProfileMediaState.completed);
        seekTo(Duration.zero).then((_) => play());
        return;
      }
      if (_repeatMode == QueueRepeatMode.off && _index >= _queue.length - 1) {
        _state.add(ProfileMediaState.completed);
        return;
      }
      _state.add(ProfileMediaState.completed);
      next();
    }
  }

  void _emitAll(ProfileMediaState s, Duration pos, Duration dur) {
    if (_disposed) return;
    _currentState = s;
    _state.add(s);
    _indexStream.add(_index);
    _position.add(pos);
    _duration.add(dur);
  }

  /// True when the whole queue is audio and the media session is available.
  ///
  /// The engine cannot render video, so a mixed queue would have to swap
  /// owners mid-play and lose the notification queue; mixed queues therefore
  /// stay on video_player.
  bool get _useAudioEngine {
    if (_queue.isEmpty) return false;
    if (!MediaAudioHandler.instance.isReady) return false;
    return _queue.every((e) => e.isAudio);
  }

  String _audioSignature() => _queue.map((e) => e.id).join('|');

  AudioRepeatMode get _audioRepeatMode => switch (_repeatMode) {
        QueueRepeatMode.off => AudioRepeatMode.off,
        QueueRepeatMode.all => AudioRepeatMode.all,
        QueueRepeatMode.one => AudioRepeatMode.one,
      };

  AudioTrack _toAudioTrack(ProfileMediaItem item) => AudioTrack(
        id: item.id,
        title: item.title,
        artist: item.artist,
        album: item.album,
        url: item.isLocalFile ? item.localPath! : item.videoUrl,
        isLocalFile: item.isLocalFile,
        artworkUrl: item.thumbnailUrl,
        duration: item.duration,
      );

  /// Subscribes once to the handler's streams. Listeners only act while the
  /// audio engine owns playback, so a later video load is unaffected.
  void _attachAudio() {
    if (_audioAttached) return;
    final handler = MediaAudioHandler.instance;
    if (!handler.isReady) return;
    _audioAttached = true;
    _audioSubs.add(handler.indexStream.listen((i) {
      if (_engine != _MediaEngine.audio || _disposed) return;
      if (i != _index) {
        _index = i;
        _indexStream.add(i);
      }
    }));
    _audioSubs.add(handler.positionStream.listen((p) {
      if (_engine != _MediaEngine.audio || _disposed) return;
      _audioPosition = p;
      _position.add(p);
    }));
    _audioSubs.add(handler.durationStream.listen((d) {
      if (_engine != _MediaEngine.audio || _disposed) return;
      _audioDuration = d;
      _duration.add(d);
    }));
    _audioSubs.add(handler.playingStream.listen((p) {
      if (_engine != _MediaEngine.audio || _disposed) return;
      _audioPlaying = p;
      _currentState =
          p ? ProfileMediaState.playing : ProfileMediaState.paused;
      _state.add(_currentState);
    }));
    _audioSubs.add(handler.completedStream.listen((_) {
      if (_engine != _MediaEngine.audio || _disposed) return;
      // Advancing is left to the player's loop mode; emitting completed lets
      // the UI show the end state without double-skipping.
      _currentState = ProfileMediaState.completed;
      _state.add(ProfileMediaState.completed);
    }));
    _audioSubs.add(handler.errorStream.listen((id) {
      if (_engine != _MediaEngine.audio || _disposed) return;
      final match = _queue.where((e) => e.id == id);
      _error = match.isNotEmpty ? match.first.title : current?.title;
      _currentState = ProfileMediaState.error;
      _state.add(ProfileMediaState.error);
    }));
  }

  Future<void> _teardownVideo() async {
    final c = _video;
    _video = null;
    if (c != null) {
      c.removeListener(_onTick);
      await c.pause();
      await c.dispose();
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _sleepTimer?.cancel();
    _sleepTicker?.cancel();
    for (final sub in _audioSubs) {
      await sub.cancel();
    }
    _audioSubs.clear();
    await _teardownVideo();
    await _state.close();
    await _indexStream.close();
    await _position.close();
    await _duration.close();
    await _mutedStream.close();
    await _speedStream.close();
    await _repeatStream.close();
    await _sleepStream.close();
  }
}
