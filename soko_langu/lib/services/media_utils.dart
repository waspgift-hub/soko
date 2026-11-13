/// Audio URL detection for the profile media queue.
///
/// Sellers can attach an audio file (voice intro, jingle, product sound) as a
/// product video URL. Audio items play through the same video_player engine —
/// which handles audio-only streams fine — but render an artwork card instead
/// of a video surface, so the queue mixes video, audio and YouTube freely.
const _audioExtensions = {
  'mp3',
  'm4a',
  'aac',
  'ogg',
  'oga',
  'ogx',
  'opus',
  'weba',
  'wav',
  'flac',
  'wma',
  'aiff',
  'aif',
  'caf',
  'amr',
  'mid',
};

/// True when [url] points at an audio file (extension check on the path, so
/// query strings like `?alt=media&token=x` don't fool it).
bool isAudioUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.path.isEmpty) return false;
  final path = uri.path.toLowerCase();
  final dot = path.lastIndexOf('.');
  if (dot == -1 || dot == path.length - 1) return false;
  return _audioExtensions.contains(path.substring(dot + 1));
}
