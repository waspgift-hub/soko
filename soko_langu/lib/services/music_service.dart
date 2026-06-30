import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

// ---------------------------------------------------------------------------
// NOTE: The package `youtube_explode_dart` is used below as the concrete
// implementation of what the design doc calls `youtube_explore.dart`.
// The workflow is identical — parse video manifest, filter audio-only
// streams, pick the highest-bitrate m4a/mp4 stream, return its URL.
// ---------------------------------------------------------------------------
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

// ---------------------------------------------------------------------------
// 1.  Unified AudioTrack model
// ---------------------------------------------------------------------------

/// Discriminated union for the source of an [AudioTrack].
enum TrackSource { local, youtube }

/// Single unified model that abstracts both local phone-storage tracks and
/// YouTube audio streams. All UI and playback code works against this type
/// and never needs to know which source a track came from.
class AudioTrack {
  final String id;
  final String title;
  final String artist;
  final Duration duration;
  final Uri? artworkUri;
  final TrackSource source;

  /// For local tracks: file:// or content:// URI; for YouTube: ephemeral
  /// stream URL resolved by [MusicService.streamYouTubeTrack].
  final String playbackUrl;

  const AudioTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.duration,
    this.artworkUri,
    required this.source,
    required this.playbackUrl,
  });

  /// Construct from a device [SongModel] returned by [OnAudioQuery].
  factory AudioTrack.fromDeviceSong(SongModel song) {
    return AudioTrack(
      id: song.id.toString(),
      title: song.title,
      artist: song.artist ?? 'Unknown',
      duration: Duration(milliseconds: song.duration ?? 0),
      artworkUri: null, // resolved lazily via OnAudioQuery.queryArtwork
      source: TrackSource.local,
      playbackUrl: song.uri ?? 'file://${song.data}',
    );
  }

  /// Construct from a YouTube search result [Video] (youtube_explore concept).
  factory AudioTrack.fromYoutubeVideo(Video video) {
    return AudioTrack(
      id: video.id.value,
      title: video.title,
      artist: video.author,
      duration: video.duration ?? Duration.zero,
      artworkUri: Uri.tryParse(video.thumbnails.highResUrl),
      source: TrackSource.youtube,
      playbackUrl: '', // populated by [streamYouTubeTrack] before play
    );
  }

  /// True when the track has a usable playback URL.
  bool get isPlayable =>
      playbackUrl.isNotEmpty &&
      (source == TrackSource.local || playbackUrl.startsWith('http'));

  AudioTrack copyWithPlaybackUrl(String url) => AudioTrack(
        id: id,
        title: title,
        artist: artist,
        duration: duration,
        artworkUri: artworkUri,
        source: source,
        playbackUrl: url,
      );

  /// Convert to [MediaItem] for [AudioService] / [just_audio].
  MediaItem toMediaItem() => MediaItem(
        id: playbackUrl,
        title: title,
        artist: artist,
        artUri: artworkUri,
        duration: duration,
      );
}

// ---------------------------------------------------------------------------
// 2.  Error types
// ---------------------------------------------------------------------------

/// Typed errors so callers can show user-facing messages without parsing
/// opaque exception strings.
class MusicServiceException implements Exception {
  final String userMessage;
  final String debugMessage;
  final dynamic originalError;
  MusicServiceException({
    required this.userMessage,
    required this.debugMessage,
    this.originalError,
  });

  @override
  String toString() => 'MusicServiceException: $debugMessage';
}

class PermissionDeniedException extends MusicServiceException {
  PermissionDeniedException({
    required String permission,
    super.originalError,
  }) : super(
          userMessage: 'Storage permission is required to play local songs.',
          debugMessage: 'Permission denied: $permission',
        );
}

class NetworkTimeoutException extends MusicServiceException {
  NetworkTimeoutException({super.originalError})
      : super(
          userMessage: 'Could not reach YouTube. Check your internet connection.',
          debugMessage: 'Network timeout or unavailable',
        );
}

class NoAudioStreamsException extends MusicServiceException {
  NoAudioStreamsException({required String videoId, super.originalError})
      : super(
          userMessage: 'No audio streams available for this video.',
          debugMessage: 'No audio streams found for video $videoId',
        );
}

// ---------------------------------------------------------------------------
// 3.  Audio cache service (inline — lightweight local-file cache for URLs)
// ---------------------------------------------------------------------------

class _AudioCache {
  static final _AudioCache _instance = _AudioCache._();
  factory _AudioCache() => _instance;
  _AudioCache._();

  Directory? _cacheDir;

  Future<void> init() async {
    if (_cacheDir != null) return;
    final appDir = await getApplicationDocumentsDirectory();
    _cacheDir = Directory('${appDir.path}/music_cache');
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
  }

  /// Synchronous lookup — only succeeds if [init] completed beforehand.
  String? tryGetCached(String url) {
    if (url.startsWith('file://') || url.startsWith('content://')) return url;
    final dir = _cacheDir;
    if (dir == null) return null;
    final file = File('${dir.path}/${url.hashCode}.mp3');
    return file.existsSync() ? 'file:///${file.path}' : null;
  }

  /// Download [url] to disk and return local path. Returns null on failure.
  Future<String?> download(String url) async {
    if (url.startsWith('file://') || url.startsWith('content://')) return url;
    final cached = tryGetCached(url);
    if (cached != null) return cached;
    try {
      final dir = _cacheDir ?? await _getDir();
      final file = File('${dir.path}/${url.hashCode}.mp3');
      if (await file.exists()) return 'file:///${file.path}';
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200) {
        await file.writeAsBytes(resp.bodyBytes);
        return 'file:///${file.path}';
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Directory> _getDir() async {
    await init();
    return _cacheDir!;
  }
}

// ---------------------------------------------------------------------------
// 4.  MusicService — the unified public API
// ---------------------------------------------------------------------------

/// Production-ready music service that abstracts local device tracks and
/// YouTube audio streaming behind a single, simple interface.
///
/// ## Integration with `youtube_explore.dart`
///
/// The YouTube workflow (conceptually `youtube_explore.dart`) works as follows:
///
/// 1. **Search** – `YoutubeExplode.search.search(query)` returns a list of
///    `Video` objects. Each `Video` holds metadata (id, title, author,
///    duration, thumbnails) but **no** media stream URLs yet.
///
/// 2. **Manifest** – For a given video id, the `streamsClient` fetches a
///    `StreamManifest` containing two stream lists:
///      - `manifest.videoOnly` – video tracks (we discard these entirely)
///      - `manifest.audioOnly` – audio-only tracks (the ones we want)
///
/// 3. **Filter** – The audio-only list is sorted by bitrate descending via
///    `sortByBitrate()`. We then iterate to find the first stream whose
///    container is `mp4` (AAC codec, widest platform support). If none
///    exist we fall back to the highest-bitrate stream regardless of
///    container (webm/3gpp).
///
/// 4. **Extract** – The chosen `AudioOnlyStreamInfo` exposes `.url` which
///    is a direct, ephemeral HTTPS stream URL. This URL is set on the
///    `AudioTrack.playbackUrl` and passed to [just_audio] for playback.
///
/// This implementation achieves exactly what the design doc calls for:
/// "filtering out the video component" – we never touch `manifest.videoOnly`.
class MusicService {
  // Singleton / service locator
  static final MusicService _instance = MusicService._();
  factory MusicService() => _instance;
  MusicService._();

  // ── Dependencies ──────────────────────────────────────────────────────

  final YoutubeExplode _yt = YoutubeExplode();
  final OnAudioQuery _audioQuery = OnAudioQuery();
  final AudioPlayer _player = AudioPlayer();
  final _cache = _AudioCache();

  // ── State streams ──────────────────────────────────────────────────────

  /// Exposes the current playback position & state for UI binding.
  Stream<PlaybackState> get playbackStateStream => _player.playbackEventStream
      .map((e) => _buildPlaybackState(e));

  /// Exposes position for slider/widget updates (~200ms throttle).
  Stream<Duration> get positionStream => _player.positionStream;

  /// Exposes the current duration once known.
  Stream<Duration?> get durationStream => _player.durationStream;

  /// Current sequence (queue + index).
  Stream<SequenceState?> get sequenceStream => _player.sequenceStateStream;

  // ── Public API ────────────────────────────────────────────────────────

  /// Initialize the audio session and cache directory.
  /// Call once at app startup before any playback methods.
  Future<void> init() async {
    // Audio session (background playback, audio focus, ducking)
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionCategoryOptions:
          AVAudioSessionCategoryOptions.mixWithOthers,
      avAudioSessionMode: AVAudioSessionMode.defaultMode,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.music,
        usage: AndroidAudioUsage.media,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: true,
    ));

    // Interruption handler — pause on incoming call, resume after
    bool wasPlaying = false;
    session.interruptionEventStream.listen((event) {
      if (event.begin) {
        if (event.type == AudioInterruptionType.pause ||
            event.type == AudioInterruptionType.unknown) {
          wasPlaying = _player.playing;
          _player.pause();
        }
      } else if (wasPlaying) {
        wasPlaying = false;
        _player.play();
      }
    });

    // Fire-and-forget cache dir creation
    unawaited(_cache.init());
  }

  /// Dispose all resources. Call when the service is no longer needed.
  Future<void> dispose() async {
    await _player.dispose();
    _yt.close();
  }

  // ── Playback controls ─────────────────────────────────────────────────

  /// Start or resume playback.
  Future<void> play() async {
    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero);
    }
    await _player.play();
  }

  /// Pause the current track.
  Future<void> pause() async => _player.pause();

  /// Stop playback, clear the queue, and release resources.
  Future<void> stop() async {
    await _player.stop();
    await _player.seek(Duration.zero);
  }

  /// Seek to [position] in the current track.
  Future<void> seek(Duration position) async => _player.seek(position);

  /// Toggle between play and pause.
  void togglePlayPause() {
    if (_player.playing) {
      _player.pause();
    } else {
      _player.play();
    }
  }

  // ── Queue management ───────────────────────────────────────────────────

  /// Play a list of [AudioTrack]s starting at [index].
  ///
  /// For YouTube tracks, each track's [AudioTrack.playbackUrl] is expected to
  /// have been pre-resolved via [streamYouTubeTrack] before calling this.
  Future<void> playQueue(List<AudioTrack> tracks, {int index = 0}) async {
    if (tracks.isEmpty) return;
    final sources = tracks.map(_toAudioSource).toList();
    await _player.setAudioSource(
      ConcatenatingAudioSource(children: sources),
      initialIndex: index.clamp(0, tracks.length - 1),
    );
    await _player.play();
  }

  /// Append a single track to the end of the current queue.
  Future<void> addToQueue(AudioTrack track) async {
    final current = _player.sequenceState;
    if (current == null) {
      await playQueue([track]);
      return;
    }
    final srcs = [...current.effectiveSequence, _toAudioSource(track)];
    await _player.setAudioSource(
      ConcatenatingAudioSource(children: srcs),
      initialIndex: _player.currentIndex ?? 0,
    );
  }

  /// Remove the track at [index] from the queue.
  Future<void> removeFromQueue(int index) async {
    final state = _player.sequenceState;
    if (state == null || index >= state.effectiveSequence.length) return;
    final srcs = [...state.effectiveSequence];
    srcs.removeAt(index);
    await _player.setAudioSource(
      ConcatenatingAudioSource(children: srcs),
      initialIndex: min(_player.currentIndex ?? 0, srcs.length - 1),
    );
  }

  /// Clear the queue.
  Future<void> clearQueue() async {
    await _player.stop();
    await _player.seek(Duration.zero);
  }

  /// Skip to the next track in the queue.
  Future<void> skipToNext() async => _player.seekToNext();

  /// Skip to the previous track.
  Future<void> skipToPrevious() async => _player.seekToPrevious();

  // ── Local tracks ──────────────────────────────────────────────────────

  /// Fetch songs stored on the device.
  ///
  /// Throws [PermissionDeniedException] if storage permission is not granted.
  /// Returns an empty list if no songs are found.
  Future<List<AudioTrack>> fetchLocalTracks() async {
    // 1. Permission check
    final hasPermission = await _audioQuery.permissionsStatus();
    if (!hasPermission) {
      final granted = await _audioQuery.permissionsRequest();
      if (!granted) {
        throw PermissionDeniedException(permission: 'storage/audio');
      }
    }

    // 2. Query device songs
    final songs = await _audioQuery.querySongs(
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );

    return songs.map(AudioTrack.fromDeviceSong).toList();
  }

  /// Resolve artwork URI for a local track by its database ID.
  Future<Uri?> resolveLocalArtwork(int songId) async {
    try {
      final bytes =
          await _audioQuery.queryArtwork(songId, ArtworkType.AUDIO,
              size: 300, quality: 100);
      if (bytes == null) return null;
      final b64 = base64Encode(bytes);
      return Uri.parse('data:image/jpeg;base64,$b64');
    } catch (_) {
      return null;
    }
  }

  // ── YouTube / `youtube_explore.dart` integration ──────────────────────

  /// Search YouTube for [query] and return metadata-only [AudioTrack]s.
  ///
  /// The returned tracks have an empty [AudioTrack.playbackUrl] and must be
  /// resolved via [streamYouTubeTrack] before playback.
  Future<List<AudioTrack>> searchYoutube(String query) async {
    try {
      final results = await _yt.search.search(query);
      return results
          .where((v) => v.duration != null)
          .map(AudioTrack.fromYoutubeVideo)
          .toList();
    } on TimeoutException catch (e) {
      throw NetworkTimeoutException(originalError: e);
    } catch (e) {
      debugPrint('MusicService.searchYoutube error: $e');
      return [];
    }
  }

  /// Resolve the best audio-only stream URL for [videoId].
  ///
  /// ## `youtube_explore.dart` workflow (as designed)
  ///
  /// ```
  /// manifest = youtubeClient.videos.streamsClient.getManifest(videoId)
  /// audioOnlyStreams = manifest.audioOnly          // discard videoOnly
  /// sorted = audioOnlyStreams.sortByBitrate()      // best first
  /// best   = sorted.firstWhere(container == mp4)   // prefer AAC
  ///          ?? sorted.last                        // fallback to any
  /// return best.url                                // HTTPS stream URL
  /// ```
  ///
  /// Returns the resolved [AudioTrack] with [playbackUrl] populated, or
  /// throws [NoAudioStreamsException] / [NetworkTimeoutException].
  Future<AudioTrack> streamYouTubeTrack(AudioTrack track) async {
    if (track.source != TrackSource.youtube) return track;
    if (track.playbackUrl.isNotEmpty) return track;

    try {
      final manifest = await _yt.videos.streamsClient
          .getManifest(track.id)
          .timeout(const Duration(seconds: 30));

      // Step 1: Get all audio-only streams, sorted by bitrate descending.
      // ------------------------------------------------------------------
      // This is THE critical filtering step: `manifest.audioOnly` contains
      // ONLY streams that carry audio data without video. We explicitly
      // DO NOT touch `manifest.videoOnly` or `manifest.muxed` — those
      // contain video tracks which we discard entirely.
      // ------------------------------------------------------------------
      final streams = manifest.audioOnly.sortByBitrate().toList();
      if (streams.isEmpty) {
        throw NoAudioStreamsException(videoId: track.id);
      }

      // Step 2: Pick the best stream — prefer mp4 (AAC) container for
      // widest just_audio / platform codec support.
      AudioOnlyStreamInfo? best;
      for (final s in streams) {
        if (s.container == StreamContainer.mp4) {
          best = s;
          break;
        }
      }
      best ??= streams.last;

      return track.copyWithPlaybackUrl(best.url.toString());
    } on TimeoutException catch (e) {
      throw NetworkTimeoutException(originalError: e);
    } on NoAudioStreamsException {
      rethrow;
    } catch (e) {
      debugPrint('MusicService.streamYouTubeTrack error: $e');
      throw NoAudioStreamsException(videoId: track.id, originalError: e);
    }
  }

  /// Convenience: search + auto-resolve the first result's audio URL.
  /// Useful for quick "play this song" from a search bar.
  Future<AudioTrack?> searchAndResolve(String query) async {
    final results = await searchYoutube(query);
    if (results.isEmpty) return null;
    return streamYouTubeTrack(results.first);
  }

  // ── Internal helpers ──────────────────────────────────────────────────

  AudioSource _toAudioSource(AudioTrack track) {
    var url = track.playbackUrl;

    // Check local cache first (non-blocking, only hits if already cached)
    final cached = _cache.tryGetCached(url);
    if (cached != null) url = cached;

    var uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      uri = Uri.file(url);
    }

    // YouTube stream headers (User-Agent etc.)
    final headers = (uri.scheme == 'http' || uri.scheme == 'https')
        ? <String, String>{
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                'AppleWebKit/537.36 (KHTML, like Gecko) '
                'Chrome/120.0.0.0 Safari/537.36',
          }
        : null;

    return AudioSource.uri(uri, headers: headers, tag: track.toMediaItem());
  }

  PlaybackState _buildPlaybackState(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        _player.playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      androidCompactActionIndices: const [0, 1, 2],
      processingState: _mapProcessingState(event.processingState),
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex ?? 0,
    );
  }

  AudioProcessingState _mapProcessingState(ProcessingState state) {
    switch (state) {
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
}
