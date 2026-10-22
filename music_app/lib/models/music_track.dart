class MusicTrack {
  final String id;
  final String title;
  final String artist;
  final String image;
  final String? streamUrl;
  final String? downloadUrl;
  final bool downloadAllowed;

  const MusicTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.image,
    this.streamUrl,
    this.downloadUrl,
    this.downloadAllowed = false,
  });

  factory MusicTrack.fromJson(Map<String, dynamic> json) {
    return MusicTrack(
      id: '${json['id'] ?? ''}',
      title: '${json['title'] ?? 'Unknown title'}',
      artist: '${json['artist'] ?? 'Unknown artist'}',
      image: '${json['image'] ?? ''}',
      streamUrl: json['streaming_url']?.toString(),
      downloadUrl: json['audiodownload']?.toString(),
      downloadAllowed: json['audiodownload_allowed'] == true || json['audiodownload_allowed'] == 1,
    );
  }
}
