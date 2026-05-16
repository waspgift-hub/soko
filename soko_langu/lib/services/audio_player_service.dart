import 'dart:async';
import 'dart:math';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:on_audio_query/on_audio_query.dart';
import 'package:audio_service/audio_service.dart';

enum PlayerRepeatMode { off, all, one }

class AudioPlayerService extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  AudioPlayerService._() {
    _init();
  }
  static final AudioPlayerService _instance = AudioPlayerService._();
  static AudioPlayerService get instance => _instance;
  factory AudioPlayerService() => _instance;

  final ja.AudioPlayer _player = ja.AudioPlayer();
  List<SongModel> songs = [];
  int? currentIndex;
  bool shuffle = false;
  PlayerRepeatMode repeatMode = PlayerRepeatMode.off;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool isPlaying = false;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;

  StreamSubscription? _playerStateSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _processingSub;

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
  }

  void _onPlayerStateChanged(ja.PlayerState state) {
    isPlaying = state.playing;
    playbackState.add(
      playbackState.value.copyWith(
        playing: state.playing,
        processingState: state.processingState == ja.ProcessingState.ready
            ? AudioProcessingState.ready
            : state.processingState == ja.ProcessingState.loading
                ? AudioProcessingState.loading
                : state.processingState == ja.ProcessingState.buffering
                    ? AudioProcessingState.buffering
                    : AudioProcessingState.idle,
        controls: [
          MediaControl.skipToPrevious,
          if (state.playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        updatePosition: _player.position,
      ),
    );
  }

  void _onProcessingStateChanged(ja.ProcessingState state) {
    if (state == ja.ProcessingState.completed) {
      _advanceToNext();
    }
  }

  void playSong(int index) {
    if (index < 0 || index >= songs.length) return;
    final song = songs[index];
    if (song.data.isEmpty) return;
    currentIndex = index;
    mediaItem.add(
      MediaItem(
        id: song.data,
        title: song.title,
        artist: song.artist ?? 'Unknown Artist',
        artUri: Uri.tryParse(
          'content://media/external/audio/albumart/${song.albumId}',
        ),
        duration: Duration(milliseconds: song.duration ?? 0),
      ),
    );
    _player.setAudioSource(ja.AudioSource.file(song.data));
    _player.play();
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

  void toggleShuffle() => shuffle = !shuffle;

  void cycleRepeat() {
    repeatMode = switch (repeatMode) {
      PlayerRepeatMode.off => PlayerRepeatMode.all,
      PlayerRepeatMode.all => PlayerRepeatMode.one,
      PlayerRepeatMode.one => PlayerRepeatMode.off,
    };
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  @override
  Future<void> play() async {
    if (currentIndex != null) {
      await _player.play();
    }
  }

  @override
  Future<void> pause() async {
    await _player.pause();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
  }

  @override
  Future<void> skipToNext() async => next();

  @override
  Future<void> skipToPrevious() async => previous();

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    shuffle = shuffleMode == AudioServiceShuffleMode.all;
  }

  @override
  Future<void> onTaskRemoved() async {
    _player.pause();
  }

  void dispose() {
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _processingSub?.cancel();
    _player.dispose();
  }
}
