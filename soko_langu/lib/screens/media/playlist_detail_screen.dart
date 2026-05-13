import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../services/playlist_service.dart';
import '../../services/audio_player_service.dart';
import '../../models/music_playlist.dart';
import '../../extensions/context_tr.dart';

class PlaylistDetailScreen extends StatefulWidget {
  final MusicPlaylist playlist;
  final List<SongModel> allSongs;
  final VoidCallback onPlaylistChanged;

  const PlaylistDetailScreen({
    super.key,
    required this.playlist,
    required this.allSongs,
    required this.onPlaylistChanged,
  });

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  final _service = PlaylistService();
  final _audio = AudioPlayerService.instance;
  List<SongModel> _songs = [];

  @override
  void initState() {
    super.initState();
    _resolveSongs();
  }

  void _resolveSongs() {
    final paths = widget.playlist.songPaths.toSet();
    _songs = widget.allSongs.where((s) => paths.contains(s.data)).toList();
  }

  void _playAll() {
    if (_songs.isEmpty) return;
    _audio.playSong(widget.allSongs.indexOf(_songs[0]));
  }

  void _playSong(int index) {
    final songIndex = widget.allSongs.indexOf(_songs[index]);
    if (songIndex >= 0) {
      _audio.playSong(songIndex);
    }
  }

  Future<void> _removeSong(SongModel song) async {
    await _service.removeSong(widget.playlist.name, song.data);
    widget.onPlaylistChanged();
    if (mounted) {
      setState(() => _resolveSongs());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Removed from ${widget.playlist.name}')),
      );
    }
  }

  Future<void> _deletePlaylist() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('delete_playlist')),
        content: Text('Delete "${widget.playlist.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              context.tr('delete'),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _service.delete(widget.playlist.name);
      widget.onPlaylistChanged();
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.playlist.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _deletePlaylist,
          ),
        ],
      ),
      body: SafeArea(
        child: _songs.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.music_note, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      context.tr('no_songs_in_playlist'),
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              )
            : Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2D6A4F), Color(0xFF40916C)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.queue_music,
                          color: Colors.white,
                          size: 48,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${_songs.length} songs',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _playAll,
                            icon: const Icon(Icons.play_arrow),
                            label: Text(context.tr('play_all')),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF2D6A4F),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _songs.length,
                      itemBuilder: (_, i) {
                        final song = _songs[i];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            leading: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFFD8F3DC),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.music_note,
                                color: Color(0xFF2D6A4F),
                              ),
                            ),
                            title: Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: Text(
                              song.artist ?? context.tr('unknown'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                color: Colors.red,
                              ),
                              onPressed: () => _removeSong(song),
                            ),
                            onTap: () => _playSong(i),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
