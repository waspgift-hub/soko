import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:audio_service/audio_service.dart';

enum PlayerRepeatMode { off, all, one }

class AudioPlayerService extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  AudioPlayerService._() {
    player.onPlayerComplete.listen((_) => next());
    player.onPositionChanged.listen((p) => position = p);
    player.onDurationChanged.listen((d) => duration = d);
  }
  static final AudioPlayerService _instance = AudioPlayerService._();
  static AudioPlayerService get instance => _instance;
  factory AudioPlayerService() => _instance;

  final AudioPlayer player = AudioPlayer();

  List<SongModel> songs = [];
  int? currentIndex;
  bool isPlaying = false;
  bool shuffle = false;
  PlayerRepeatMode repeatMode = PlayerRepeatMode.off;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;

  void playSong(int index) {
    if (index < 0 || index >= songs.length) return;
    final song = songs[index];
    if (song.data.isEmpty) return;
    currentIndex = index;
    isPlaying = true;
    player.stop();
    player.play(DeviceFileSource(song.data));
    mediaItem.add(
      MediaItem(
        id: song.data,
        title: song.title,
        artist: song.artist ?? 'Unknown Artist',
        duration: Duration(milliseconds: song.duration ?? 0),
      ),
    );
    playbackState.add(
      PlaybackState(
        processingState: AudioProcessingState.ready,
        playing: true,
        controls: [
          MediaControl.skipToPrevious,
          MediaControl.pause,
          MediaControl.skipToNext,
        ],
        systemActions: {MediaAction.seek},
        updatePosition: Duration.zero,
      ),
    );
  }

  void togglePlayPause() {
    if (currentIndex == null) return;
    if (isPlaying) {
      player.pause();
      isPlaying = false;
    } else {
      player.resume();
      isPlaying = true;
    }
    playbackState.add(playbackState.value.copyWith(playing: isPlaying));
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
    await player.seek(position);
  }

  void dispose() {
    player.dispose();
  }

  @override
  Future<void> play() async {
    if (currentIndex != null) {
      await player.resume();
      isPlaying = true;
      playbackState.add(playbackState.value.copyWith(playing: true));
    }
  }

  @override
  Future<void> pause() async {
    await player.pause();
    isPlaying = false;
    playbackState.add(playbackState.value.copyWith(playing: false));
  }

  @override
  Future<void> stop() async {
    await player.stop();
    isPlaying = false;
    playbackState.add(
      playbackState.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.idle,
      ),
    );
  }

  @override
  Future<void> skipToNext() async => next();

  @override
  Future<void> skipToPrevious() async => previous();

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    shuffle = shuffleMode == AudioServiceShuffleMode.all;
  }
}
