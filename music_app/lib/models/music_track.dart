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
    return MusicTrack(
      id: '${json['id'] ?? ''}',
      title: '${json['title'] ?? 'Unknown title'}',
      artist: '${json['artist'] ?? 'Unknown artist'}',
      image: '${json['image'] ?? ''}',
      streamUrl: json['streaming_url']?.toString(),
    );
  }
}
