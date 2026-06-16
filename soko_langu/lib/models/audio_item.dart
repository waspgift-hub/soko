class AudioItem {
  final String id;
  final String title;
  final String artist;
  final String url;
  final String? imageUrl;
  final Duration duration;

  const AudioItem({
    required this.id,
    required this.title,
    required this.artist,
    required this.url,
    this.imageUrl,
    this.duration = Duration.zero,
  });
}
