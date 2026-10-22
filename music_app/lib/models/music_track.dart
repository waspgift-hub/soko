class MusicTrack {
  final String id;
  final String title;
  final String artist;
  final String image;
  final String? streamUrl;

  const MusicTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.image,
    this.streamUrl,
  });

  factory MusicTrack.fromJson(Map<String, dynamic> json) {
    // Accept the app's normalized shape as well as Jamendo's public API shape.
    final id = (json['id'] ?? json['track_id'] ?? '').toString();
    final stream = json['streaming_url'] ?? json['audio'] ?? json['audio_url'];
    final image = json['image'] ?? json['album_image'] ?? json['image_url'] ?? json['cover'];
    return MusicTrack(
      id: id,
      title: (json['title'] ?? json['name'] ?? 'Unknown title').toString(),
      artist: (json['artist'] ?? json['artist_name'] ?? 'Unknown artist').toString(),
      image: (image ?? '').toString(),
      streamUrl: stream == null || stream.toString().trim().isEmpty
          ? null
          : stream.toString(),
    );
  }
}
