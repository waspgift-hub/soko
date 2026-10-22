class MusicTrack {
  final String id;
  final String title;
  final String artist;
  final String image;
  final String? streamUrl;
  final String? downloadUrl;
  final bool downloadAllowed;
  final String source;

  const MusicTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.image,
    this.streamUrl,
    this.downloadUrl,
    this.downloadAllowed = false,
    this.source = 'licensed',
  });

  factory MusicTrack.fromJson(Map<String, dynamic> json) {
    final rawDownloadAllowed = json['audiodownload_allowed'];
    final downloadAllowed = rawDownloadAllowed == true ||
        rawDownloadAllowed == 1 ||
        rawDownloadAllowed?.toString() == '1';

    return MusicTrack(
      id: '${json['id'] ?? ''}',
      title: '${json['title'] ?? json['song'] ?? 'Unknown title'}',
      artist: '${json['artist'] ?? 'Unknown artist'}',
      image: '${json['image'] ?? json['cover'] ?? ''}',
      // Jamendo Worker payloads expose stream and licensed-download URLs.
      // Playback resolves /play/:id separately to validate the stream URL.
      streamUrl: (json['streaming_url'] ?? json['audio'])?.toString(),
      downloadUrl: (json['audiodownload'] ?? json['download'])?.toString(),
      downloadAllowed: downloadAllowed,
      source: '${json['source'] ?? 'licensed'}',
    );
  }
}
