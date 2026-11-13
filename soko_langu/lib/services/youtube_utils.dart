/// YouTube URL helpers for the profile media queue.
///
/// SCOPE: this exists for YouTube RESULTS in the music tab, not for seller
/// product videos. Sellers upload their own video file (see
/// add_product_screen.dart `_pickVideo` → Cloudflare R2) and it plays through
/// the normal video_player engine; no seller-facing screen anywhere accepts a
/// YouTube URL for a listing.
///
/// Why YouTube is not a seller-video path: YouTube never serves directly
/// playable mp4 URLs, so an embedded link only plays while the uploader permits
/// embedding. That permission is the uploader's choice, and YouTube answers 101
/// / 150 / 153 — "cannot play inside the app" — when it is withheld. Music
/// videos in particular almost always have embedding disabled, so a feature
/// built on embedded YouTube looks broken in exactly the place users try it.
///
/// The helpers below therefore only recognise a YouTube link so it can be
/// played through the privacy-enhanced nocookie embed, with an explicit
/// "watch on YouTube" escape when the uploader says no.
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

/// Local HTML wrapper around the official YouTube IFrame Player API.
///
/// A bare iframe URL fails silently (or with a cryptic "video player
/// configuration error", code 153) when a video can't be embedded. The API
/// wrapper reports `onError` codes and playback states back through the
/// `YouTubeError` / `YouTubeState` JavaScript channels so the app can show a
/// friendly fallback (or auto-advance on end) instead of a dead frame.
String youTubeEmbedHtml(String videoId) {
  return '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<style>html,body{margin:0;padding:0;background:#000;height:100%;overflow:hidden}#p{position:absolute;top:0;left:0;width:100%;height:100%}</style>
</head>
<body><div id="p"></div>
<script src="https://www.youtube.com/iframe_api"></script>
<script>
var player;
function onYouTubeIframeAPIReady() {
  player = new YT.Player('p', {
    height: '100%', width: '100%', videoId: '$videoId',
    playerVars: { rel: 0, playsinline: 1, autoplay: 1 },
    events: {
      onError: function (e) { YouTubeError.postMessage(String(e.data)); },
      onStateChange: function (e) { YouTubeState.postMessage(String(e.data)); }
    }
  });
}
</script>
</body>
</html>
''';
}

/// IFrame API state codes we care about (YT.PlayerState.ENDED).
const youTubeStateEnded = '0';
