import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/music_playlist.dart';

class PlaylistService {
  static const String _key = 'music_playlists';

  Future<List<MusicPlaylist>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_key);
    if (data == null) return [];
    final list = jsonDecode(data) as List;
    return list.map((e) => MusicPlaylist.fromJson(e)).toList();
  }

  Future<void> save(List<MusicPlaylist> playlists) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(playlists.map((p) => p.toJson()).toList()),
    );
  }

  Future<void> create(String name, List<String> songPaths) async {
    final playlists = await load();
    playlists.add(
      MusicPlaylist(
        name: name,
        songs: songPaths.map((p) => PlaylistSong.fromPath(p)).toList(),
      ),
    );
    await save(playlists);
  }

  Future<void> delete(String name) async {
    final playlists = await load();
    playlists.removeWhere((p) => p.name == name);
    await save(playlists);
  }

  Future<void> addSongs(String playlistName, List<String> paths) async {
    final playlists = await load();
    final idx = playlists.indexWhere((p) => p.name == playlistName);
    if (idx == -1) return;
    final existing = playlists[idx].songPaths.toSet();
    for (final path in paths) {
      if (!existing.contains(path)) {
        playlists[idx].songs.add(PlaylistSong.fromPath(path));
      }
    }
    await save(playlists);
  }

  Future<void> removeSong(String playlistName, String path) async {
    final playlists = await load();
    final idx = playlists.indexWhere((p) => p.name == playlistName);
    if (idx == -1) return;
    playlists[idx].songs.removeWhere((s) => s.path == path);
    if (playlists[idx].songs.isEmpty) {
      playlists.removeAt(idx);
    }
    await save(playlists);
  }
}
