/// Kind of playable media a [SokoMediaItem] represents.
enum SokoMediaType { audio, video }

/// A single playable item — song or video — from the local device.
///
/// Every source (MediaStore scan, native video query, manual file pick) is
/// normalized into this shape so the UI and the player service never need to
/// know where an item came from. [uri] is either a content:// URI (library
/// scans on Android) or a file:// URI (manual imports).
class SokoMediaItem {
  const SokoMediaItem({
    required this.id,
    required this.title,
    required this.uri,
    required this.type,
    this.artist,
    this.album,
    this.duration = Duration.zero,
    this.artUri,
    this.fromImport = false,
  });

  /// Stable identity within the library (MediaStore id, or path for imports).
  final String id;
  final String title;

  /// Display name of the artist — null for ringtones/recordings without tags.
  final String? artist;
  final String? album;

  /// content:// URI for library items, file:// URI for imported files.
  final String uri;
  final SokoMediaType type;
  final Duration duration;

  /// Cached album-art file URI (file://). Null when no art is available.
  final String? artUri;
  final bool fromImport;

  /// Artist fallback so the UI never shows a blank subtitle row.
  String get subtitle =>
      (artist?.isNotEmpty == true) ? artist! : (album?.isNotEmpty == true ? album! : '');

  SokoMediaItem copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    String? uri,
    SokoMediaType? type,
    Duration? duration,
    String? artUri,
    bool? fromImport,
  }) {
    return SokoMediaItem(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      uri: uri ?? this.uri,
      type: type ?? this.type,
      duration: duration ?? this.duration,
      artUri: artUri ?? this.artUri,
      fromImport: fromImport ?? this.fromImport,
    );
  }
}