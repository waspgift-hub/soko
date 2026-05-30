import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:on_audio_query/on_audio_query.dart';

enum PlayerRepeatMode { off, all, one }

class AudioPlayerService {
  AudioPlayerService._() {
    _init();
  }
  static final AudioPlayerService _instance = AudioPlayerService._();
  static AudioPlayerService get instance => _instance;
  factory AudioPlayerService() => _instance;

  final ja.AudioPlayer _player = ja.AudioPlayer(
    audioPipeline: ja.AudioPipeline(
      androidAudioEffects: [
        ja.AndroidLoudnessEnhancer(),
      ],
    ),
  );
  List<SongModel> songs = [];
  int? currentIndex;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool isPlaying = false;

  final ValueNotifier<bool> shuffleNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<PlayerRepeatMode> repeatNotifier =
      ValueNotifier<PlayerRepeatMode>(PlayerRepeatMode.off);

  bool get shuffle => shuffleNotifier.value;
  set shuffle(bool value) => shuffleNotifier.value = value;

  PlayerRepeatMode get repeatMode => repeatNotifier.value;
  set repeatMode(PlayerRepeatMode value) => repeatNotifier.value = value;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<bool> get playingStream => _player.playingStream;
  Stream<int?> get currentIndexStream => _currentIndexController.stream;
  final _currentIndexController = StreamController<int?>.broadcast();

  StreamSubscription? _playerStateSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _processingSub;
  StreamSubscription? _currentIndexSub;

  void _init() {
    _playerStateSub = _player.playerStateStream.listen(_onPlayerStateChanged);
    _positionSub = _player.positionStream.listen((p) {
      position = p;
    });
    _durationSub = _player.durationStream.listen((d) {
      duration = d ?? Duration.zero;
    });
    _processingSub = _player.processingStateStream
        .listen(_onProcessingStateChanged);
    _currentIndexSub = _currentIndexController.stream.listen((idx) {
      currentIndex = idx;
    });
  }

  void _onPlayerStateChanged(ja.PlayerState state) {
    isPlaying = state.playing;
  }

  void _onProcessingStateChanged(ja.ProcessingState state) {
    if (state == ja.ProcessingState.completed) {
      _advanceToNext();
    }
  }

  Future<void> playSong(int index) async {
    if (index < 0 || index >= songs.length) return;
    final song = songs[index];
    if (song.data.isEmpty) return;
    try {
      await _player.setFilePath(song.data);
      _currentIndexController.add(index);
      await _player.play();
    } catch (e) {
      debugPrint('playSong error: $e');
    }
  }

  void togglePlayPause() {
    if (currentIndex == null) return;
    if (isPlaying) {
      _player.pause();
    } else {
      _player.play();
    }
  }

  void togglePlayPauseFromIndex(int index) {
    if (currentIndex == index) {
      togglePlayPause();
    } else {
      playSong(index);
    }
  }

  void _advanceToNext() {
    if (songs.isEmpty) return;
    if (repeatMode == PlayerRepeatMode.one) {
      playSong(currentIndex!);
      return;
    }
    int next;
    if (shuffle) {
      next = _randomIndex();
    } else {
      next = (currentIndex! + 1) % songs.length;
    }
    playSong(next);
  }

  void next() {
    if (currentIndex == null || songs.isEmpty) return;
    if (repeatMode == PlayerRepeatMode.one) {
      playSong(currentIndex!);
      return;
    }
    int next;
    if (shuffle) {
      next = _randomIndex();
    } else {
      next = (currentIndex! + 1) % songs.length;
    }
    playSong(next);
  }

  void previous() {
    if (currentIndex == null || songs.isEmpty) return;
    if (repeatMode == PlayerRepeatMode.one) {
      playSong(currentIndex!);
      return;
    }
    if (_player.position.inSeconds > 3) {
      _player.seek(Duration.zero);
      return;
    }
    int prev;
    if (shuffle) {
      prev = _randomIndex();
    } else {
      prev = (currentIndex! - 1 + songs.length) % songs.length;
    }
    playSong(prev);
  }

  int _randomIndex() {
    if (songs.length <= 1) return 0;
    int idx;
    do {
      idx = Random().nextInt(songs.length);
    } while (idx == currentIndex);
    return idx;
  }

  void toggleShuffle() {
    shuffle = !shuffle;
  }

  void cycleRepeat() {
    repeatMode = switch (repeatMode) {
      PlayerRepeatMode.off => PlayerRepeatMode.all,
      PlayerRepeatMode.all => PlayerRepeatMode.one,
      PlayerRepeatMode.one => PlayerRepeatMode.off,
    };
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  Future<void> stop() async {
    await _player.stop();
    _currentIndexController.add(null);
  }

  void dispose() {
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _processingSub?.cancel();
    _currentIndexSub?.cancel();
    _currentIndexController.close();
    shuffleNotifier.dispose();
    repeatNotifier.dispose();
    _player.dispose();
  }
}
