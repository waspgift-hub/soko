import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/audio_player_service.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/google_loading.dart';
import '../../widgets/audio_player_widgets.dart';
import '../../models/music_playlist.dart';

class MediaPlayerScreen extends StatefulWidget {
  const MediaPlayerScreen({super.key});
  @override
  State<MediaPlayerScreen> createState() => _MediaPlayerScreenState();
}

class _MediaPlayerScreenState extends State<MediaPlayerScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  final AudioPlayerService _audio = AudioPlayerService.instance;
  List<MusicPlaylist> _playlists = [];
  bool _hasAudioPermission = false;
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
    _loadPlaylists();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_hasAudioPermission) _checkPermissions();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    if (!Platform.isAndroid) {
      return setState(() => _isLoading = false);
    }
    for (final p in [Permission.audio, Permission.storage]) {
      if (await p.status.isGranted) {
        _hasAudioPermission = true;
      }
    }
    if (_hasAudioPermission) await _loadSongs();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _requestAudioPermission() async {
    setState(() => _isLoading = true);
    for (final p in [Permission.audio, Permission.storage]) {
      if (await p.request().isGranted) {
        setState(() => _hasAudioPermission = true);
        await _loadSongs();
        if (mounted) setState(() => _isLoading = false);
        return;
      }
    }
    if (mounted) await _handleDenied();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _handleDenied() async {
    if (!mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('permission_required')),
        content: const Text(
          'Permission was denied. Open app settings to enable it manually.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('open_settings')),
          ),
        ],
      ),
    );
    if (go == true) await openAppSettings();
  }

  Future<void> _loadSongs() async {
    final songs = await _audioQuery.querySongs(
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );
    if (mounted) {
      _audio.loadSongs(songs);
      setState(() => _isLoading = false);
    }
  }



  Future<void> _loadPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('music_playlists');
    if (data != null) {
      final list = jsonDecode(data) as List;
      setState(
        () => _playlists = list.map((e) => MusicPlaylist.fromJson(e)).toList(),
      );
    }
  }

  Future<void> _savePlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'music_playlists',
      jsonEncode(_playlists.map((p) => p.toJson()).toList()),
    );
  }

  String _fmt(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  void _openFullPlayer() {
    if (_audio.currentIndex == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AudioFullPlayerPage(
          onAddToPlaylist: _addCurrentToPlaylist,
        ),
      ),
    );
  }

  List<SongModel> get _filteredSongs {
    if (_searchQuery.isEmpty) return _audio.songs;
    final q = _searchQuery.toLowerCase();
    return _audio.songs
        .where(
          (s) =>
              s.title.toLowerCase().contains(q) ||
              (s.artist ?? '').toLowerCase().contains(q),
        )
        .toList();
  }

  Future<void> _addCurrentToPlaylist() async {
    if (_audio.currentIndex == null) return;
    final song = _audio.songs[_audio.currentIndex!];
    if (song.data.isEmpty) return;
    final playlist = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(context.tr('add_to_playlist')),
        children: [
          ..._playlists.map(
            (p) => SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, p.name),
              child: Text(p.name),
            ),
          ),
          if (_playlists.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(context.tr('no_playlists')),
            ),
        ],
      ),
    );
    if (playlist != null) {
      setState(() {
        final idx = _playlists.indexWhere((p) => p.name == playlist);
        if (idx >= 0 &&
            !_playlists[idx].songs.any((s) => s.path == song.data)) {
          _playlists[idx].songs.add(PlaylistSong.fromPath(song.data));
        }
      });
      await _savePlaylists();
    }
  }

  Future<void> _addToPlaylist(int songIndex) async {
    final song = _audio.songs[songIndex];
    if (song.data.isEmpty) return;
    final playlist = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(context.tr('add_to_playlist')),
        children: [
          ..._playlists.map(
            (p) => SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, p.name),
              child: Text(p.name),
            ),
          ),
          if (_playlists.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(context.tr('no_playlists')),
            ),
        ],
      ),
    );
    if (playlist != null) {
      setState(() {
        final idx = _playlists.indexWhere((p) => p.name == playlist);
        if (idx >= 0 &&
            !_playlists[idx].songs.any((s) => s.path == song.data)) {
          _playlists[idx].songs.add(PlaylistSong.fromPath(song.data));
        }
      });
      await _savePlaylists();
    }
  }

  void _showCreatePlaylistSheet() {
    final nameCtrl = TextEditingController();
    final selected = <int>{};
    String query = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final songs = query.isEmpty
                ? _audio.songs
                : _audio.songs
                      .where(
                        (s) =>
                            s.title.toLowerCase().contains(query.toLowerCase()),
                      )
                      .toList();

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.8,
                child: Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: nameCtrl,
                        decoration: InputDecoration(
                          hintText: context.tr('playlist_name'),
                          prefixIcon: const Icon(Icons.playlist_play),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: context.tr('search_songs'),
                          prefixIcon: const Icon(Icons.search, size: 20),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          isDense: true,
                        ),
                        onChanged: (v) => setSheetState(() => query = v),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Text(
                            '${songs.length} songs',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              setSheetState(() {
                                if (selected.length == songs.length) {
                                  selected.clear();
                                } else {
                                  selected.addAll(
                                    List.generate(songs.length, (i) => i),
                                  );
                                }
                              });
                            },
                            child: Text(
                              selected.length == songs.length &&
                                      songs.isNotEmpty
                                  ? context.tr('deselect_all')
                                  : context.tr('select_all'),
                              style: TextStyle(color: Theme.of(context).colorScheme.primary),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 0),
                    Expanded(
                      child: songs.isEmpty
                          ? Center(
                              child: Text(
                                query.isEmpty
                                    ? context.tr('no_songs')
                                    : 'No songs match "$query"',
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                            )
                          : ListView.builder(
                              itemCount: songs.length,
                              itemBuilder: (context, index) {
                                final song = songs[index];
                                final checked = selected.contains(index);
                                return ListTile(
                                  leading: QueryArtworkWidget(
                                    id: song.id,
                                    type: ArtworkType.AUDIO,
                                    nullArtworkWidget: Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        Icons.music_note,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        size: 20,
                                      ),
                                    ),
                                    artworkFit: BoxFit.cover,
                                    artworkBorder: BorderRadius.circular(8),
                                    size: 44,
                                  ),
                                  title: Text(
                                    song.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  subtitle: Text(
                                    song.artist ?? context.tr('unknown_artist'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  trailing: Checkbox(
                                    value: checked,
                                    activeColor: Theme.of(context).colorScheme.primary,
                                    onChanged: (v) {
                                      setSheetState(() {
                                        v == true
                                            ? selected.add(index)
                                            : selected.remove(index);
                                      });
                                    },
                                  ),
                                  onTap: () {
                                    setSheetState(() {
                                      selected.contains(index)
                                          ? selected.remove(index)
                                          : selected.add(index);
                                    });
                                  },
                                );
                              },
                            ),
                    ),
                    if (songs.isNotEmpty)
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Theme.of(context).colorScheme.primary,
                                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: selected.isEmpty
                                  ? null
                                  : () {
                                      final name = nameCtrl.text.trim();
                                      if (name.isEmpty) return;
                                      final playlist = MusicPlaylist(
                                        name: name,
                                        songs: selected
                                            .map((i) => PlaylistSong.fromPath(songs[i].data))
                                            .toList(),
                                      );
                                      setState(() {
                                        _playlists.add(playlist);
                                      });
                                      _savePlaylists();
                                      Navigator.pop(ctx);
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Playlist "$name" created '
                                            'with ${selected.length} songs',
                                          ),
                                          backgroundColor: Theme.of(context).colorScheme.primary,
                                        ),
                                      );
                                    },
                              child: Text(
                                '${context.tr('create_playlist')} (${selected.length})',
                                style: const TextStyle(fontSize: 15),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
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
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          context.tr('my_media'),
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: _isLoading
          ? const GoogleLoadingPage()
          : _buildAudioTab(),
      bottomNavigationBar: AudioMiniPlayer(onOpenFullPlayer: _openFullPlayer),
    );
  }

  // â”€â”€â”€ AUDIO TAB â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildAudioTab() {
    if (!_hasAudioPermission) return _buildPermissionView();
    if (_audio.songs.isEmpty) {
      return _buildEmptyView(Icons.music_note, context.tr('no_songs'));
    }
    final visible = _filteredSongs;

    return Column(
      children: [
        AudioSearchField(
          query: _searchQuery,
          onChanged: (v) => setState(() => _searchQuery = v),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.playlist_play),
                  label: Text(
                    '${context.tr('play_all')} (${visible.length})',
                    style: const TextStyle(fontSize: 14),
                  ),
                  onPressed: visible.isEmpty
                      ? null
                      : () async {
                          final idx = _audio.songs.indexOf(visible.first);
                          if (idx >= 0) {
                            try {
                              await _audio.playSong(idx);
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('${context.tr('error')}: $e')),
                                );
                              }
                            }
                          }
                        },
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  side: BorderSide(color: Theme.of(context).colorScheme.primary),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Playlist', style: TextStyle(fontSize: 13)),
                onPressed: _showCreatePlaylistSheet,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: _audio,
            builder: (context, _) {
              if (visible.isEmpty) {
                return Center(
                  child: Text(
                    context.tr('no_songs'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }
              return ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: visible.length,
            itemBuilder: (context, index) {
              final song = visible[index];
              final songIndex = _audio.songs.indexOf(song);
              final isCurrent = _audio.currentIndex == songIndex;
              return ListTile(
                leading: QueryArtworkWidget(
                  id: song.id,
                  type: ArtworkType.AUDIO,
                  nullArtworkWidget: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? Theme.of(context).colorScheme.primary.withAlpha(25)
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.music_note,
                      color: isCurrent ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  artworkFit: BoxFit.cover,
                  artworkBorder: BorderRadius.circular(8),
                ),
                title: Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                    color: isCurrent ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                subtitle: Text(
                  song.artist ?? context.tr('unknown_artist'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                trailing: Text(
                  _fmt(Duration(milliseconds: song.duration ?? 0)),
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                onTap: () async {
                  try {
                    await _audio.togglePlayPauseFromIndex(songIndex);
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('${context.tr('error')}: $e')),
                      );
                    }
                  }
                },
                onLongPress: () => _addToPlaylist(songIndex),
              );
            },
          );
            },
          ),
        ),
      ],
    );
  }

  // â”€â”€â”€ PERMISSION VIEW â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildPermissionView() {
    return SafeArea(
      child: SingleChildScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 20,
        ),
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withAlpha(15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.music_note_rounded,
                  size: 50,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Audio Player',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Allow access to your music files to play audio.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Tap 'Allow Access' to grant permission.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                  icon: const Icon(Icons.check_circle),
                  label: Text(
                    context.tr('allow_access'),
                    style: const TextStyle(fontSize: 16),
                  ),
                  onPressed: _requestAudioPermission,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyView(IconData icon, String msg) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(msg, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
