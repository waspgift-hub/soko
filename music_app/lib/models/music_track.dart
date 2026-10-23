class MusicTrack {
  final String id;
  final String title;
  final String artist;
  final String? album;
  final String image;
  final String? streamUrl;
  final String? streamLookupUrl;
  final String? sourceUrl;
  final String? downloadUrl;
  final bool audiodownloadAllowed;
  final String license;
  final int durationSeconds;
  final String source;

  const MusicTrack({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    required this.image,
    this.streamUrl,
    this.streamLookupUrl,
    this.sourceUrl,
    this.downloadUrl,
    this.audiodownloadAllowed = false,
    this.license = '',
    this.durationSeconds = 0,
    this.source = 'jamendo',
  });

  String get artistAlbumLabel {
    final albumName = album?.trim();
    return albumName == null || albumName.isEmpty ? artist : '$artist • $albumName';
  }

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
      artist: '${json['artist'] ?? json['creator'] ?? 'Unknown artist'}',
      album: (json['album'] ?? json['album_name'])?.toString(),
      image: _httpsOrEmpty(
        (json['image'] ?? json['cover'])?.toString(),
      ),
      streamUrl: _httpsOrNull(
        (json['streaming_url'] ?? json['streamUrl'] ?? json['audio'])?.toString(),
      ),
      streamLookupUrl: _safeLookupPath(json['streamLookupUrl']?.toString()),
      sourceUrl: _httpsOrNull((json['sourceUrl'] ?? json['share_url'])?.toString()),
      downloadUrl: _httpsOrNull(
        (json['audiodownload'] ?? json['download'])?.toString(),
      ),
      audiodownloadAllowed: allowed,
      license: '${json['license'] ?? ''}',
      durationSeconds: int.tryParse('${json['duration'] ?? 0}') ?? 0,
      source: '${json['source'] ?? json['provider'] ?? 'jamendo'}'.toLowerCase(),
    );
  }

  factory MusicTrack.fromLocalJson(Map<String, dynamic> json) => MusicTrack(
        id: '${json['id'] ?? ''}',
        title: '${json['title'] ?? 'Unknown title'}',
        artist: '${json['artist'] ?? 'Unknown artist'}',
        album: json['album']?.toString(),
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
        'album': album,
        'image': image,
        'streaming_url': streamUrl,
        'streamLookupUrl': streamLookupUrl,
        'sourceUrl': sourceUrl,
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

  static String? _safeLookupPath(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    if (uri.hasScheme) {
      return uri.scheme == 'https' && uri.host.isNotEmpty ? uri.toString() : null;
    }
    return uri.path.startsWith('/api/v1/catalog/play/internet-archive/')
        ? uri.toString()
        : null;
  }
}
