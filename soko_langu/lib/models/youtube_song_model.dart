class YoutubeSong {
  final String id;
  final String title;
  final String artist;
  final Duration duration;
  final String thumbnailUrl;
  String? audioUrl;

  YoutubeSong({
    required this.id,
    required this.title,
    required this.artist,
    required this.duration,
    required this.thumbnailUrl,
    this.audioUrl,
  });

  String get videoUrl => 'https://www.youtube.com/watch?v=$id';

  String get durationFormatted {
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    final s = duration.inSeconds.remainder(60);
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
