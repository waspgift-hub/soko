import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../models/soko_media_item.dart';
import 'media_library_service.dart';

/// Global singleton owning the single just_audio player for the app.
///
/// just_audio_background permits exactly ONE [AudioPlayer] per process, so
/// this service creates it once and reuses it for every queue. Playback state
/// (current item, position, playing flag) is broadcast via [ChangeNotifier]
/// so the mini player and Now Playing screen stay in sync. Notification and
/// lock-screen controls come from the same player after
/// `JustAudioBackground.init` has run in main().
class MediaPlayerService extends ChangeNotifier {
  MediaPlayerService._() {
    _setupSubscriptions();
  }

  static final MediaPlayerService instance = MediaPlayerService._();

  final AudioPlayer _player = AudioPlayer();

  List<SokoMediaItem> _queue = const [];
  SokoMediaItem? _current;
  bool _active = false;
  bool _queueLoading = false;
  Duration _position = Duration.zero;
  bool _shuffle = false;
  LoopMode _loop = LoopMode.off;

  // Streams pass through unchanged for widgets that want their own rebuild
  // cadence (e.g. the seek slider ticking at the player's 200ms rate).
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<bool> get playingStream => _player.playingStream;
  Stream<LoopMode> get loopModeStream => _player.loopModeStream;
  Stream<SequenceState?> get sequenceStateStream => _player.sequenceStateStream;

  /// Queue in the original (non-shuffled) play order.
  List<SokoMediaItem> get queue => _queue;

  /// Currently playing item, resolved from the player's MediaItem tag so it
  /// stays correct regardless of shuffle/repeat.
  SokoMediaItem? get current => _current;

  /// Original-queue index of the current item (null when nothing plays).
  int? get currentIndex =>
      _current == null ? null : _queue.indexWhere((m) => m.id == _current!.id);

  bool get active => _active;
  bool get queueLoading => _queueLoading;
  bool get playing => _player.playing;
  bool get shuffle => _shuffle;
  LoopMode get loop => _loop;
  Duration get position => _position;
  Duration? get duration => _player.duration;

  /// Position clamped to the track duration so the slider never overflows.
  Duration get safePosition {
    final d = duration;
    if (d != null && _position > d) return d;
    return _position;
  }

  void _setupSubscriptions() {
    _player.playbackEventStream.listen((event) {
      // just_audio 0.10 moved shuffle/loop state off PlaybackEvent and onto
      // the player; the current source (with its MediaItem tag) comes from
      // the SequenceState which is keyed to the same event index.
      final tag = _player.sequenceState.currentSource?.tag;
      _current = tag is MediaItem
          ? _queue.where((m) => m.id == tag.id).firstOrNull
          : null;
      _shuffle = _player.shuffleModeEnabled;
      _loop = _player.loopMode;
      notifyListeners();
    }, onError: (Object e) {
      debugPrint('MediaPlayerService: playback event error — $e');
    });

    // 500ms cadence is enough for the mini player + seek slider; the slider
    // additionally ticks at full 200ms rate through its own stream.
    _player.positionStream.listen((p) {
      _position = p;
      notifyListeners();
    }, onError: (Object e) {
      debugPrint('MediaPlayerService: position stream error — $e');
    });
  }

  /// Loads [queue] into the player and starts playing at [startIndex].
  ///
  /// Album art is resolved for the whole queue before the source is set so the
  /// notification art is correct for every track, not just the first one.
  /// Re-entering with the same queue URI list only seeks+plays — it never
  /// rebuilds the audio source (which would drop the current position).
  Future<void> playQueue(List<SokoMediaItem> queue, {int startIndex = 0}) async {
    if (queue.isEmpty) return;
    if (_active && _sameUriQueue(queue)) {
      final target = _clampIndex(startIndex);
      if (target != currentIndex) {
        await _player.seek(Duration.zero, index: target);
      }
      await _player.play();
      notifyListeners();
      return;
    }

    _queueLoading = true;
    notifyListeners();
    try {
      final arts = await MediaLibraryService.instance.resolveArtwork(queue);
      _queue = [
        for (var i = 0; i < queue.length; i++)
          arts[i] == null ? queue[i] : queue[i].copyWith(artUri: arts[i]),
      ];
      final concat = ConcatenatingAudioSource(
        children: [
          for (final item in _queue)
            AudioSource.uri(
              Uri.parse(item.uri),
              tag: MediaItem(
                id: item.id,
                title: item.title,
                artist: item.subtitle.isEmpty ? null : item.subtitle,
                album: item.album,
                duration: item.duration > Duration.zero ? item.duration : null,
                artUri:
                    item.artUri == null ? null : Uri.tryParse(item.artUri!),
              ),
            ),
        ],
      );
      await _player.setAudioSource(
        concat,
        initialIndex: _clampIndex(startIndex),
      );
      _active = true;
      await _player.play();
    } catch (e) {
      debugPrint('MediaPlayerService.playQueue: $e');
    } finally {
      _queueLoading = false;
      notifyListeners();
    }
  }

  /// Continues playback of the current track without rebuilding the queue.
  Future<void> toggle() async {
    if (!_active || _current == null) return;
    if (_player.playing) {
      await _player.pause();
    } else {
      // Restart from the end so a finished track replays instead of re-pausing
      // in a dead state.
      if (_player.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero);
      }
      await _player.play();
    }
  }

  Future<void> pause() async {
    if (_player.playing) await _player.pause();
  }

  Future<void> play() async {
    if (_current == null) return;
    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero);
    }
    await _player.play();
  }

  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> next() => _player.seekToNext();

  Future<void> previous() => _player.seekToPrevious();

  /// Jumps to an original-order queue index; works even while shuffled.
  Future<void> jumpTo(int originalIndex) async {
    if (originalIndex < 0 || originalIndex >= _queue.length) return;
    // When shuffled the internal index space is different — disable shuffle
    // around the jump is NOT needed: seek(index:) always targets the
    // unshuffled sequence position.
    await _player.seek(Duration.zero, index: originalIndex);
    await _player.play();
  }

  Future<void> setShuffleEnabled(bool enabled) async {
    _shuffle = enabled;
    await _player.setShuffleModeEnabled(enabled);
    notifyListeners();
  }

  Future<void> setLoopMode(LoopMode mode) async {
    _loop = mode;
    await _player.setLoopMode(mode);
    notifyListeners();
  }

  Future<void> cycleLoop() async {
    final modes = const [LoopMode.off, LoopMode.all, LoopMode.one];
    final next = modes[(modes.indexOf(_loop) + 1) % modes.length];
    await setLoopMode(next);
  }

  /// Stops playback and drops the queue (also dismisses the notification).
  Future<void> clear() async {
    await _player.stop();
    _queue = const [];
    _current = null;
    _active = false;
    _position = Duration.zero;
    notifyListeners();
  }

  bool _sameUriQueue(List<SokoMediaItem> other) {
    if (other.length != _queue.length) return false;
    for (var i = 0; i < other.length; i++) {
      if (other[i].uri != _queue[i].uri) return false;
    }
    return true;
  }

  int _clampIndex(int i) => i.clamp(0, _queue.length - 1);
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}