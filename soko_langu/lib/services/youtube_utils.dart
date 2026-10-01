/// YouTube URL helpers for the profile media queue.
///
/// Sellers paste plain YouTube links (watch / youtu.be / shorts / live /
/// embed) as a product video. YouTube never serves directly playable mp4
/// URLs, so these links play through the privacy-enhanced nocookie embed in
/// a WebView instead of the video_player engine.
bool _validVideoId(String id) =>
    RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id);

/// Extracts the 11-character YouTube video id from every common URL shape.
/// Returns null when [url] is not a YouTube link.
String? youTubeIdFromUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.host.isEmpty) return null;
  final host = uri.host.toLowerCase();

  if (host == 'youtu.be') {
    final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
    return _validVideoId(id) ? id : null;
  }

  if (host == 'youtube.com' ||
      host == 'm.youtube.com' ||
      host.endsWith('.youtube.com') ||
      host.endsWith('.youtube-nocookie.com')) {
    if (uri.path == '/watch') {
      final id = uri.queryParameters['v'] ?? '';
      return _validVideoId(id) ? id : null;
    }
    final segments = uri.pathSegments;
    if (segments.length >= 2 &&
        (segments[0] == 'shorts' ||
            segments[0] == 'live' ||
            segments[0] == 'embed' ||
            segments[0] == 'v')) {
      return _validVideoId(segments[1]) ? segments[1] : null;
    }
  }
  return null;
}

bool isYouTubeUrl(String url) => youTubeIdFromUrl(url) != null;

/// Embed URL rendered in the in-app WebView. nocookie domain + no related
/// videos keeps tracking and end-screen upsells out of the marketplace.
String youTubeEmbedUrl(String videoId) =>
    'https://www.youtube-nocookie.com/embed/$videoId?rel=0&playsinline=1&autoplay=1';
