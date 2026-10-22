class MusicTrack {
  final String id;
  final String title;
  final String artist;
  final String image;
  final String? streamUrl;
  final String license;
  final int durationSeconds;

  const MusicTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.image,
    this.streamUrl,
    this.license = '',
    this.durationSeconds = 0,
  });

  factory MusicTrack.fromJson(Map<String, dynamic> json) => MusicTrack(
    id: '${json['id'] ?? ''}',
    title: '${json['title'] ?? 'Unknown title'}',
    artist: '${json['artist'] ?? 'Unknown artist'}',
    image: '${json['image'] ?? ''}',
    streamUrl: json['streaming_url']?.toString(),
    license: '${json['license'] ?? ''}',
    durationSeconds: int.tryParse('${json['duration'] ?? 0}') ?? 0,
  );
}