import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:on_audio_query/on_audio_query.dart';

enum PlayerRepeatMode { off, all, one }

/// Singleton audio engine with queue, lock-screen controls, and reactive UI.
class AudioPlayerService extends ChangeNotifier {
  AudioPlayerService._() {
    _init();
  }

  static final AudioPlayerService _instance = AudioPlayerService._();
  static AudioPlayerService get instance => _instance;
  factory AudioPlayerService() => _instance;

  final AudioPlayer _player = AudioPlayer();
  final Completer<void> _initCompleter = Completer<void>();
  bool _initDone = false;

  List<SongModel> songs = [];
  int? currentIndex;

  void loadSongs(List<SongModel> newSongs) {
    songs = newSongs;
    _queueSignature = null;
    notifyListeners();
  }
  bool shuffle = false;
  PlayerRepeatMode repeatMode = PlayerRepeatMode.off;

  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool isPlaying = false;
  bool isBuffering = false;

  String? _queueSignature;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<bool> get playingStream => _player.playingStream;

  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<ProcessingState>? _processingSub;
  StreamSubscription<SequenceState?>? _sequenceSub;

  Future<void> _initAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: false,
      ));
    } catch (e) {
      debugPrint('AudioSession: $e');
    }
  }

  Future<void> _ensureInitialized() async {
    if (!_initDone) await _initCompleter.future;
  }

  Future<void> _init() async {
    try {
      await _initAudioSession();
      if (defaultTargetPlatform == TargetPlatform.android) {
        await Permission.notification.request();
      }
      _player.setVolume(1.0);
      _player.setSpeed(1.0);
      _player.setAndroidAudioAttributes(
        AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
        ),
      );
      _playerStateSub = _player.playerStateStream.listen((state) {
        isPlaying = state.playing;
        isBuffering =
            state.processingState == ProcessingState.loading ||
            state.processingState == ProcessingState.buffering;
        notifyListeners();
      });

      _positionSub = _player.positionStream.listen((p) {
        position = p;
        notifyListeners();
      });

      _durationSub = _player.durationStream.listen((d) {
        duration = d ?? Duration.zero;
        notifyListeners();
      });

      _processingSub = _player.processingStateStream.listen((state) {
        if (state == ProcessingState.completed &&
            repeatMode == PlayerRepeatMode.off &&
            currentIndex != null &&
            currentIndex! >= songs.length - 1) {
          isPlaying = false;
          notifyListeners();
        }
      });

      _sequenceSub = _player.sequenceStateStream.listen((state) {
        final idx = state?.currentIndex;
        if (idx != null && idx != currentIndex) {
          currentIndex = idx;
          notifyListeners();
        }
      });
    } catch (e) {
      debugPrint('AudioPlayerService._init error: $e');
    }
    _initDone = true;
    if (!_initCompleter.isCompleted) _initCompleter.complete();
  }

  String _computeSignature() => songs.map((s) => '${s.id}:${s.data}').join('|');

  Uri? _uriForSong(SongModel song) {
    final data = song.data;
    if (data.isEmpty) return null;
    if (data.startsWith('content://') ||
        data.startsWith('file://') ||
        data.startsWith('http')) {
      return Uri.parse(data);
    }
    return Uri.file(data);
  }

  MediaItem _mediaItemFor(SongModel song) => MediaItem(
    id: '${song.id}',
    title: song.title,
    artist: song.artist ?? 'Unknown Artist',
    duration: Duration(milliseconds: song.duration ?? 0),
  );

  List<AudioSource> _buildSources() {
    final sources = <AudioSource>[];
    for (final song in songs) {
      final uri = _uriForSong(song);
      if (uri == null) continue;
      sources.add(AudioSource.uri(uri, tag: _mediaItemFor(song)));
    }
    return sources;
  }

  Future<void> _applyRepeatAndShuffle() async {
    await _player.setShuffleModeEnabled(shuffle);
    if (shuffle) await _player.shuffle();
    switch (repeatMode) {
      case PlayerRepeatMode.off:
        await _player.setLoopMode(LoopMode.off);
      case PlayerRepeatMode.all:
        await _player.setLoopMode(LoopMode.all);
      case PlayerRepeatMode.one:
        await _player.setLoopMode(LoopMode.one);
    }
  }

  Future<void> _ensureQueue({required int startIndex}) async {
    final signature = _computeSignature();
    if (_queueSignature == signature && _player.audioSource != null) {
      final idx = startIndex.clamp(0, songs.length - 1);
      await _player.seek(Duration.zero, index: idx);
      return;
    }

    final sources = _buildSources();
    if (sources.isEmpty) return;

    final idx = startIndex.clamp(0, sources.length - 1);
    await _player.setAudioSource(
      ConcatenatingAudioSource(children: sources),
      initialIndex: idx,
      initialPosition: Duration.zero,
    );
    _queueSignature = signature;
    await _applyRepeatAndShuffle();
  }

  Future<void> playSong(int index) async {
    await _ensureInitialized();
    if (index < 0 || index >= songs.length) return;
    final song = songs[index];
    if (song.data.isEmpty) return;

    await _ensureQueue(startIndex: index);
    currentIndex = _player.currentIndex ?? index;
    await _player.setVolume(1.0);
    await _player.play();
    notifyListeners();
  }

  Future<void> playSongs(List<SongModel> playlist, {int startIndex = 0}) async {
    songs = playlist;
    _queueSignature = null;
    await playSong(startIndex);
  }

  Future<void> togglePlayPause() async {
    if (currentIndex == null && songs.isNotEmpty) {
      await playSong(0);
      return;
    }
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> togglePlayPauseFromIndex(int index) async {
    if (currentIndex == index && _player.audioSource != null) {
      await togglePlayPause();
    } else {
      await playSong(index);
    }
  }

  Future<void> next() async {
    if (songs.isEmpty) return;
    try {
      if (_player.hasNext) {
        await _player.seekToNext();
      } else if (repeatMode == PlayerRepeatMode.all) {
        await _player.seek(Duration.zero, index: 0);
      }
      currentIndex = _player.currentIndex ?? currentIndex;
      notifyListeners();
    } catch (e) {
      debugPrint('AudioPlayerService.next: $e');
    }
  }

  Future<void> previous() async {
    if (songs.isEmpty) return;
    try {
      if (_player.position.inSeconds > 3) {
        await _player.seek(Duration.zero);
        notifyListeners();
        return;
      }
      if (_player.hasPrevious) {
        await _player.seekToPrevious();
      } else if (repeatMode == PlayerRepeatMode.all) {
        await _player.seek(Duration.zero, index: songs.length - 1);
      }
      currentIndex = _player.currentIndex ?? currentIndex;
      notifyListeners();
    } catch (e) {
      debugPrint('AudioPlayerService.previous: $e');
    }
  }

  Future<void> seek(Duration pos) async {
    try {
      await _player.seek(pos);
      notifyListeners();
    } catch (e) {
      debugPrint('AudioPlayerService.seek: $e');
    }
  }

  Future<void> seekRelative(Duration delta) async {
    final target = position + delta;
    final max = duration;
    if (max > Duration.zero && target > max) {
      await next();
      return;
    }
    await seek(target < Duration.zero ? Duration.zero : target);
  }

  Future<void> toggleShuffle() async {
    shuffle = !shuffle;
    await _applyRepeatAndShuffle();
    notifyListeners();
  }

  Future<void> cycleRepeat() async {
    repeatMode = switch (repeatMode) {
      PlayerRepeatMode.off => PlayerRepeatMode.all,
      PlayerRepeatMode.all => PlayerRepeatMode.one,
      PlayerRepeatMode.one => PlayerRepeatMode.off,
    };
    await _applyRepeatAndShuffle();
    notifyListeners();
  }

  SongModel? get currentSong {
    final idx = currentIndex;
    if (idx == null || idx < 0 || idx >= songs.length) return null;
    return songs[idx];
  }

  @override
  void dispose() {
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _processingSub?.cancel();
    _sequenceSub?.cancel();
    _player.dispose();
    super.dispose();
  }
}
