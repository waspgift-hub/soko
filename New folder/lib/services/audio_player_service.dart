import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'media_session_service.dart';

enum PlayerRepeatMode { off, all, one }

class AudioPlayerService {
  AudioPlayerService._() {
    _init();
  }
  static final AudioPlayerService _instance = AudioPlayerService._();
  static AudioPlayerService get instance => _instance;
  factory AudioPlayerService() => _instance;

  final MediaSessionService _native = MediaSessionService.instance;

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

  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _playingController = StreamController<bool>.broadcast();
  final _currentIndexController = StreamController<int?>.broadcast();

  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration?> get durationStream => _durationController.stream;
  Stream<bool> get playingStream => _playingController.stream;
  Stream<int?> get currentIndexStream => _currentIndexController.stream;

  StreamSubscription<Map<String, dynamic>>? _stateSub;

  void _init() {
    _stateSub = _native.stateStream.listen(_onNativeStateChanged);
  }

  void _onNativeStateChanged(Map<String, dynamic> state) {
    final playing = state['playing'] as bool? ?? false;
    final idx = state['currentIndex'] as int? ?? -1;
    final pos = state['position'] as int? ?? 0;
    final dur = state['duration'] as int? ?? 0;

    isPlaying = playing;
    if (idx >= 0) {
      currentIndex = idx;
    }
    position = Duration(milliseconds: pos);
    duration = Duration(milliseconds: dur);

    _playingController.add(playing);
    _currentIndexController.add(idx >= 0 ? idx : null);
    _positionController.add(position);
    _durationController.add(duration);
  }

  bool _playlistInitialized = false;

  Future<void> initPlaylist() async {
    final songMaps = songs.asMap().entries.map((e) {
      final song = e.value;
      final artUri = song.albumId != null
          ? 'content://media/external/audio/albumart/${song.albumId}'
          : null;
      return {
        'index': e.key,
        'filePath': song.data,
        'title': song.title,
        'artist': song.artist ?? '',
        'album': song.album ?? '',
        'durationMs': song.duration ?? 0,
        if (artUri != null) 'artUri': artUri,
      };
    }).toList();
    await _native.initPlaylist(songMaps);
    _playlistInitialized = true;
  }

  void resetPlaylist() {
    _playlistInitialized = false;
  }

  Future<void> playSong(int index) async {
    if (index < 0 || index >= songs.length) return;
    final song = songs[index];
    if (song.data.isEmpty) return;

    if (!_playlistInitialized) {
      await initPlaylist();
    }
    await _native.playAtIndex(index);
  }

  void togglePlayPause() {
    _native.togglePlayPause();
  }

  void togglePlayPauseFromIndex(int index) {
    if (currentIndex == index) {
      togglePlayPause();
    } else {
      playSong(index);
    }
  }

  void next() {
    if (songs.isEmpty) return;
    _native.next();
  }

  void previous() {
    if (songs.isEmpty || currentIndex == null) return;
    if (position.inSeconds > 3) {
      _native.seekTo(Duration.zero);
      return;
    }
    _native.previous();
  }

  void toggleShuffle() {
    shuffle = !shuffle;
    _native.setShuffle(shuffle);
  }

  void cycleRepeat() {
    repeatMode = switch (repeatMode) {
      PlayerRepeatMode.off => PlayerRepeatMode.all,
      PlayerRepeatMode.all => PlayerRepeatMode.one,
      PlayerRepeatMode.one => PlayerRepeatMode.off,
    };
    _native.setRepeatMode(repeatMode.index);
  }

  Future<void> seek(Duration position) async {
    await _native.seekTo(position);
  }

  Future<void> stop() async {
    await _native.stop();
    currentIndex = null;
    position = Duration.zero;
    duration = Duration.zero;
    isPlaying = false;
  }

  void dispose() {
    _stateSub?.cancel();
    _positionController.close();
    _durationController.close();
    _playingController.close();
    _currentIndexController.close();
    shuffleNotifier.dispose();
    repeatNotifier.dispose();
  }
}
