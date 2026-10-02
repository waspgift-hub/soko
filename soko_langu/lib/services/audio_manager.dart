import 'dart:async';

import '../services/media_audio_handler.dart';
import '../services/profile_media_controller.dart';
import '../services/profile_media_session.dart';

/// Which source currently owns playback.
///
/// Top-level rather than nested because this SDK rejects enums declared inside
/// a class (`enum_in_class`).
enum PlaybackMode { none, music, video, youtube }

/// Unified audio manager that coordinates between music, video, and YouTube playback.
/// Ensures only one audio/video source plays at a time.
class AudioManager {
  AudioManager._internal();
  static final AudioManager _instance = AudioManager._internal();
  factory AudioManager() => _instance;

  PlaybackMode _mode = PlaybackMode.none;
  final MediaAudioHandler _audioHandler = MediaAudioHandler.instance;
  final ProfileMediaController _controller = ProfileMediaSession.instance.controller;

  /// Singleton access
  static AudioManager get instance => _instance;

  /// Current playback mode
  PlaybackMode get mode => _mode;

  /// Whether any audio is currently playing
  bool get isPlaying => _mode != PlaybackMode.none && (_mode == PlaybackMode.music || _isVideoOrYouTubePlaying());

  /// Core coordination method: play music queue
  Future<void> playMusic({
    required List<ProfileMediaItem> queue,
    int startAt = 0,
  }) async {
    // If music already playing, do nothing
    if (_mode == PlaybackMode.music && _isSameQueue(queue)) return;

    // Stop any other playback type
    await _stopOtherMode(PlaybackMode.music);

    // Play music through the audio handler. loadQueue takes the tracks
    // positionally; ProfileMediaItem stores the file under localPath and the
    // artwork under thumbnailUrl, so map those onto AudioTrack's fields
    // rather than assuming the two models share names.
    await _audioHandler.loadQueue(
      [
        for (final item in queue)
          AudioTrack(
            id: item.id,
            title: item.title,
            artist: item.artist,
            album: item.album,
            url: item.localPath ?? item.videoUrl,
            isLocalFile: item.localPath != null,
            artworkUrl: item.thumbnailUrl,
            duration: item.duration,
          ),
      ],
      startIndex: startAt,
      autoplay: true,
      repeatMode: AudioRepeatMode.all,
    );

    _mode = PlaybackMode.music;
  }

  /// Play a single video item, pausing music if needed
  Future<void> playVideo(ProfileMediaItem item) async {
    // If already playing this video type, do nothing
    if (_mode == PlaybackMode.video && _isSameItem(item)) return;

    // Pause music when video starts
    if (_mode == PlaybackMode.music) {
      await _audioHandler.pause();
    }

    // Set up video playback through the profile controller
    await _controller.setQueue([item], startAt: 0);
    await _controller.play();
    _mode = PlaybackMode.video;
  }

  /// Play YouTube video (inline only, no background playback)
  Future<void> playYouTube(String videoId) async {
    // YouTube playback is inline-only per YouTube Terms
    // No true background playback is permitted

    if (_mode == PlaybackMode.youtube) return;

    // Pause music if currently playing
    if (_mode == PlaybackMode.music || _mode == PlaybackMode.video) {
      await _audioHandler.pause();
    }

    // Set YouTube item in the controller queue
    // YouTube videos are identified by videoId in the URL
    final youtubeItem = ProfileMediaItem(
      id: 'youtube:$videoId',
      title: 'YouTube Video',
      videoUrl: 'https://www.youtube.com/embed/$videoId?rel=0&showinfo=0',
    );

    await _controller.setQueue([youtubeItem], startAt: 0);
    await _controller.play();
    _mode = PlaybackMode.youtube;
  }

  /// Stop all playback and reset mode
  Future<void> stopAll() async {
    await _audioHandler.release();
    await _controller.setQueue(const []);
    _mode = PlaybackMode.none;
  }

  /// Pause playback (convenience method)
  Future<void> pauseAll() async {
    await _audioHandler.pause();
  }

  /// Silences whichever source is active so only one thing plays at a time.
  ///
  /// Two players back this app — the lock-screen [MediaAudioHandler] for audio
  /// and the [ProfileMediaController] for inline video — and nothing in the
  /// platform stops one when the other starts, so the handover is explicit
  /// here. Takes the mode that is about to become active and tears down
  /// whatever currently holds the audio session.
  Future<void> _stopOtherMode(PlaybackMode incoming) async {
    if (_mode == PlaybackMode.none || _mode == incoming) return;
    if (_mode == PlaybackMode.music) {
      await _audioHandler.pause();
    } else {
      // Inline video / YouTube lives in the controller, not the handler.
      await _controller.pause();
    }
    _mode = PlaybackMode.none;
  }

/// Check if video or YouTube is currently playing
  bool _isVideoOrYouTubePlaying() {
    // Simplified check - in production would read from controller state
    return _mode == PlaybackMode.video || _mode == PlaybackMode.youtube;
  }

  /// Check if the queue is the same (avoid duplicate starts)
  bool _isSameQueue(List<ProfileMediaItem> newQueue) {
    final current = _controller.current;
    if (current == null) return false;
    if (newQueue.length != _controller.queue.length) return false;
    for (int i = 0; i < newQueue.length; i++) {
      if (newQueue[i].id != _controller.queue[i].id) return false;
    }
    return true;
  }

  /// Check if the current item is the same
  bool _isSameItem(ProfileMediaItem newItem) {
    final current = _controller.current;
    if (current == null) return false;
    return current.id == newItem.id;
  }
}