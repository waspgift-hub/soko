class PlaylistSong {
  final String path;
  final String? title;
  final String? artist;

  PlaylistSong({required this.path, this.title, this.artist});

  Map<String, dynamic> toJson() => {
    'path': path,
    if (title != null) 'title': title,
    if (artist != null) 'artist': artist,
  };

  factory PlaylistSong.fromJson(Map<String, dynamic> json) => PlaylistSong(
    path: json['path'] as String,
    title: json['title'] as String?,
    artist: json['artist'] as String?,
  );

  factory PlaylistSong.fromPath(String path) => PlaylistSong(path: path);
}

class MusicPlaylist {
  final String name;
  final List<PlaylistSong> songs;

  MusicPlaylist({required this.name, required this.songs});

  List<String> get songPaths => songs.map((s) => s.path).toList();

  Map<String, dynamic> toJson() => {
    'name': name,
    'songs': songs.map((s) => s.toJson()).toList(),
  };

  factory MusicPlaylist.fromJson(Map<String, dynamic> json) {
    final songsRaw = json['songs'];
    List<PlaylistSong> songs;
    if (songsRaw is List) {
      songs = songsRaw.map((e) {
        if (e is String) return PlaylistSong.fromPath(e);
        if (e is Map<String, dynamic>) return PlaylistSong.fromJson(e);
        return PlaylistSong.fromPath(e.toString());
      }).toList();
    } else {
      final pathsRaw = json['songPaths'];
      if (pathsRaw is List) {
        songs = pathsRaw
            .map((e) => PlaylistSong.fromPath(e.toString()))
            .toList();
      } else {
        songs = [];
      }
    }
    return MusicPlaylist(name: json['name'] as String, songs: songs);
  }
}
