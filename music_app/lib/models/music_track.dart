class MusicTrack {
  final String id;
  final String title;
  final String artist;
  final String image;
  final String? streamUrl;
  final String? downloadUrl;
  final bool audiodownloadAllowed;
  final String license;
  final int durationSeconds;
  final String source;

  const MusicTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.image,
    this.streamUrl,
    this.downloadUrl,
    this.audiodownloadAllowed = false,
    this.license = '',
    this.durationSeconds = 0,
    this.source = 'jamendo',
  });

  bool get canStream => _isHttpsUrl(streamUrl);
  bool get canDownload => audiodownloadAllowed && _isHttpsUrl(downloadUrl);
  bool get isLocal => source == 'local' || source == 'device';

  // Compatibility alias for UI code from earlier SokoVibe Music iterations.
  bool get downloadAllowed => canDownload;

  factory MusicTrack.fromJson(Map<String, dynamic> json) {
    final rawAllowed = json['audiodownload_allowed'];
    final allowed = rawAllowed == true ||
        rawAllowed == 1 ||
        rawAllowed?.toString().toLowerCase() == 'true' ||
        rawAllowed?.toString() == '1';
    return MusicTrack(
      id: '${json['id'] ?? ''}',
      title: '${json['title'] ?? json['song'] ?? 'Unknown title'}',
      artist: '${json['artist'] ?? 'Unknown artist'}',
      image: _httpsOrEmpty(
        (json['image'] ?? json['cover'])?.toString(),
      ),
      streamUrl: _httpsOrNull(
        (json['streaming_url'] ?? json['audio'])?.toString(),
      ),
      downloadUrl: _httpsOrNull(
        (json['audiodownload'] ?? json['download'])?.toString(),
      ),
      audiodownloadAllowed: allowed,
      license: '${json['license'] ?? ''}',
      durationSeconds: int.tryParse('${json['duration'] ?? 0}') ?? 0,
      source: '${json['source'] ?? 'jamendo'}'.toLowerCase(),
    );
  }

  factory MusicTrack.fromLocalJson(Map<String, dynamic> json) => MusicTrack(
        id: '${json['id'] ?? ''}',
        title: '${json['title'] ?? 'Unknown title'}',
        artist: '${json['artist'] ?? 'Unknown artist'}',
        image: '',
        streamUrl: null,
        downloadUrl: null,
        audiodownloadAllowed: false,
        license: '${json['license'] ?? ''}',
        durationSeconds:
            int.tryParse('${json['durationSeconds'] ?? 0}') ?? 0,
        source: '${json['source'] ?? 'local'}'.toLowerCase(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'artist': artist,
        'image': image,
        'streaming_url': streamUrl,
        'audiodownload': downloadUrl,
        'audiodownload_allowed': audiodownloadAllowed,
        'license': license,
        'duration': durationSeconds,
        'source': source,
      };

  static bool _isHttpsUrl(String? value) => _httpsOrNull(value) != null;

  static String? _httpsOrNull(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    return uri.toString();
  }

  static String _httpsOrEmpty(String? value) => _httpsOrNull(value) ?? '';
}
