import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/youtube_song_model.dart';

class AudioStreamInfo {
  final String url;
  final int bitrate;
  AudioStreamInfo({required this.url, required this.bitrate});
}

class YoutubeAudioService {
  final YoutubeExplode _yt = YoutubeExplode();

  Future<List<YoutubeSong>> search(String query) async {
    try {
      final results = await _yt.search.search(query);
      final songs = <YoutubeSong>[];
      for (final video in results) {
        if (video.duration != null) {
          songs.add(
            YoutubeSong(
              id: video.id.value,
              title: video.title,
              artist: video.author,
              duration: video.duration!,
              thumbnailUrl: video.thumbnails.highResUrl,
            ),
          );
        }
      }
      return songs;
    } catch (e) {
      debugPrint('YoutubeSearch error: $e');
      return [];
    }
  }

  /// Returns the best available audio stream URL for [videoId].
  ///
  /// Strategy:
  /// 1. Prefer mp4 (AAC) containers — widest just_audio support across all platforms.
  /// 2. Fall back to any audio container (webm, 3gpp).
  /// 3. Pick highest bitrate within the preferred container group.
  ///
  /// Returns `null` when the video is unplayable or has no audio streams.
  Future<AudioStreamInfo?> getBestAudioStream(String videoId) async {
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      final streams = manifest.audioOnly.sortByBitrate().toList();
      if (streams.isEmpty) return null;

      // Prefer mp4 (AAC), then highest bitrate
      AudioOnlyStreamInfo? best;
      for (final s in streams) {
        if (s.container == StreamContainer.mp4) {
          best = s;
          break;
        }
      }
      best ??= streams.isNotEmpty ? streams.last : null;
      if (best == null) return null;
      return AudioStreamInfo(
          url: best.url.toString(), bitrate: best.bitrate.bitsPerSecond);
    } on VideoUnplayableException catch (e) {
      debugPrint('VideoUnplayableException for $videoId: $e');
      return null;
    } catch (e) {
      debugPrint('getBestAudioStream error for $videoId: $e');
      return null;
    }
  }

  /// Returns the best available muxed (audio+video) stream URL for [videoId].
  ///
  /// Muxed streams contain both audio and video tracks, suitable for
  /// [VideoPlayer]. Falls back to lower resolutions if progressive is
  /// unavailable. Returns `null` if no muxed stream exists.
  Future<String?> getBestMuxedStream(String videoId) async {
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      final muxed = manifest.muxed.sortByVideoQuality().toList();
      if (muxed.isEmpty) return null;
      // Prefer lowest resolution for fastest load, or highest for quality
      return muxed.last.url.toString();
    } on VideoUnplayableException catch (e) {
      debugPrint('VideoUnplayableException for $videoId: $e');
      return null;
    } catch (e) {
      debugPrint('getBestMuxedStream error for $videoId: $e');
      return null;
    }
  }

  /// Legacy wrapper — returns just the URL string for backward compat.
  Future<String?> getAudioUrl(String videoId) async {
    final info = await getBestAudioStream(videoId);
    return info?.url;
  }

  Future<void> dispose() async {
    _yt.close();
  }
}
