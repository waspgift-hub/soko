class AudioItem {
  final String id;
  final String title;
  final String artist;
  final String url;
  final String? imageUrl;
  final Duration duration;
  final String? youtubeVideoId;

  const AudioItem({
    required this.id,
    required this.title,
    required this.artist,
    required this.url,
    this.imageUrl,
    this.duration = Duration.zero,
    this.youtubeVideoId,
  });
}
