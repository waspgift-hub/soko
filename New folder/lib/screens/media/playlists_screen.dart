import 'dart:io';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/playlist_service.dart';
import '../../models/music_playlist.dart';
import 'playlist_detail_screen.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/google_loading.dart';

class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  final _service = PlaylistService();
  final _audioQuery = OnAudioQuery();
  List<MusicPlaylist> _playlists = [];
  List<SongModel> _allSongs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (!Platform.isAndroid) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (!await Permission.audio.status.isGranted) {
      await Permission.audio.request();
    }
    if (!await Permission.storage.status.isGranted) {
      await Permission.storage.request();
    }
    try {
      final songs = await _audioQuery.querySongs(
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );
      final playlists = await _service.load();
      if (mounted) {
        setState(() {
          _allSongs = songs;
          _playlists = playlists;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('PlaylistsScreen: error loading songs — $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${context.tr('error')}: $e")),
        );
      }
      final playlists = await _service.load();
      if (mounted) {
        setState(() {
          _playlists = playlists;
          _loading = false;
        });
      }
    }
  }

  Future<void> _createPlaylist() async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('create_playlist')),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            hintText: context.tr('playlist_name'),
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, nameController.text.trim()),
            child: Text(context.tr('create')),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    final selectedPaths = await _showSongPicker();
    if (selectedPaths == null) return;

    await _service.create(name, selectedPaths);
    final playlists = await _service.load();
    if (mounted) setState(() => _playlists = playlists);
  }

  Future<List<String>?> _showSongPicker() async {
    final selected = Set<String>.of(_allSongs.map((s) => s.data));
    return showDialog<List<String>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Select Songs'),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: ListView.builder(
                  itemCount: _allSongs.length,
                  itemBuilder: (_, i) {
                    final song = _allSongs[i];
                    final isSelected = selected.contains(song.data);
                    return CheckboxListTile(
                      title: Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        song.artist ?? context.tr('unknown'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      value: isSelected,
                      onChanged: (val) {
                        setDialogState(() {
                          if (val == true) {
                            selected.add(song.data);
                          } else {
                            selected.remove(song.data);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(context.tr('cancel')),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, selected.toList()),
                  child: Text('Add (${selected.length})'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Playlists'),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: _createPlaylist),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const GoogleLoadingPage()
            : _playlists.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.queue_music, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(height: 16),
                    Text(
                      context.tr('no_playlists'),
                      style: TextStyle(fontSize: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _createPlaylist,
                      icon: const Icon(Icons.add),
                      label: Text(context.tr('create_playlist')),
                    ),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: _init,
                child: GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.9,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: _playlists.length,
                  itemBuilder: (_, i) {
                    final p = _playlists[i];
                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PlaylistDetailScreen(
                              playlist: p,
                              allSongs: _allSongs,
                              onPlaylistChanged: () async {
                                final playlists = await _service.load();
                                if (mounted) {
                                  setState(() => _playlists = playlists);
                                }
                              },
                            ),
                          ),
                        );
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF2D6A4F,
                              ).withOpacity(0.06),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                Icons.queue_music,
                                color: Theme.of(context).colorScheme.secondary,
                                size: 32,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: Text(
                                p.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Theme.of(context).colorScheme.secondary,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '${p.songs.length} songs',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}

