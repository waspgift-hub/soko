import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/music_playlist.dart';
import '../../services/audio_player_service.dart';
import '../../widgets/google_loading.dart';
import '../../widgets/audio_player_widgets.dart';
import '../../widgets/rewarded_ad_gate.dart';
import '../../extensions/context_tr.dart';

class MusicPlayerScreen extends StatefulWidget {
  const MusicPlayerScreen({super.key});

  @override
  State<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends State<MusicPlayerScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  final AudioPlayerService _service = AudioPlayerService.instance;
  List<SongModel> _songs = [];
  List<MusicPlaylist> _playlists = [];
  bool _hasPermission = false;
  bool _isLoading = true;
  int _tabIndex = 0;
  String _searchQuery = '';
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() => setState(() => _tabIndex = _tabCtrl.index));
    WidgetsBinding.instance.addPostFrameCallback((_) => _initWithAdGate());
  }

  Future<void> _initWithAdGate() async {
    final passed = await RewardedAdGate.require(
      context,
      'music_player',
      title: context.tr('watch_ad'),
      message: context.tr('watch_ad_to_music'),
    );
    if (!passed && mounted) {
      Navigator.of(context).pop();
      return;
    }
    _checkPermission();
    _loadPlaylists();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_hasPermission) {
      _checkPermission();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkPermission() async {
    final sdk = Platform.isAndroid
        ? int.tryParse(Platform.operatingSystemVersion.split(' ').last) ?? 0
        : 0;
    final perms = sdk >= 33
        ? [Permission.audio, Permission.manageExternalStorage, Permission.notification]
        : sdk >= 30
        ? [Permission.storage, Permission.manageExternalStorage]
        : [Permission.storage];
    for (final p in perms) {
      if (await p.status.isGranted) {
        setState(() => _hasPermission = true);
        _loadSongs();
        return;
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _loadSongs() async {
    try {
      final songs = await _audioQuery.querySongs(
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );
      if (mounted) {
        _service.loadSongs(songs);
        setState(() {
          _songs = songs;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('MusicPlayerScreen._loadSongs: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openFullPlayer() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AudioFullPlayerPage(
          onAddToPlaylist: _service.currentIndex != null
              ? () => _addToPlaylist(_service.currentIndex!)
              : null,
        ),
      ),
    );
  }

  List<SongModel> get _filteredSongs {
    if (_searchQuery.isEmpty) return _songs;
    final q = _searchQuery.toLowerCase();
    return _songs
        .where(
          (s) =>
              s.title.toLowerCase().contains(q) ||
              (s.artist ?? '').toLowerCase().contains(q),
        )
        .toList();
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

  Future<void> _createPlaylist() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('new_playlist')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: context.tr('playlist_name')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(context.tr('create')),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      setState(() => _playlists.add(MusicPlaylist(name: name, songs: [])));
      await _savePlaylists();
    }
  }

  Future<void> _addToPlaylist(int songIndex) async {
    final song = _songs[songIndex];
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

  void _playPlaylistSongs(List<String> paths, int startIndex) {
    if (paths.isEmpty) return;
    final path = paths[startIndex];
    final idx = _songs.indexWhere((s) => s.data == path);
    if (idx >= 0) _service.playSong(idx);
  }

  String _fmt(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          context.tr('music_player'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: _hasPermission && _songs.isNotEmpty
            ? TabBar(
                controller: _tabCtrl,
                labelColor: Theme.of(context).colorScheme.primary,
                unselectedLabelColor: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant,
                indicatorColor: Theme.of(context).colorScheme.primary,
                tabs: [
                  Tab(text: context.tr('songs')),
                  Tab(text: context.tr('playlists')),
                ],
              )
            : null,
      ),
      body: SafeArea(child: _buildBody()),
      bottomNavigationBar: AudioMiniPlayer(onOpenFullPlayer: _openFullPlayer),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const GoogleLoadingPage();

    if (!_hasPermission) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
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
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.1),
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
                context.tr('music_player'),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                context.tr('music_permission_desc'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('music_permission_hint'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
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
                  onPressed: () async {
                    setState(() => _isLoading = true);
                    final sdk = Platform.isAndroid
                        ? int.tryParse(
                                Platform.operatingSystemVersion.split(' ').last,
                              ) ??
                            0
                        : 0;
                    final perms = sdk >= 33
                        ? [Permission.audio, Permission.manageExternalStorage, Permission.notification]
                        : sdk >= 30
                        ? [Permission.storage, Permission.manageExternalStorage]
                        : [Permission.storage];
                    for (final p in perms) {
                      final status = await p.request();
                      if (status.isGranted) {
                        setState(() => _hasPermission = true);
                        _loadSongs();
                        return;
                      }
                    }
                    if (mounted) {
                      setState(() => _isLoading = false);
                      bool anyPermanentlyDenied = false;
                      for (final p in perms) {
                        if (await p.status.isPermanentlyDenied) {
                          anyPermanentlyDenied = true;
                          break;
                        }
                      }
                      if (anyPermanentlyDenied && mounted) {
                        final go = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(context.tr('permission_required')),
                            content: Text(context.tr('permission_denied_desc')),
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
                        if (go == true) {
                          await openAppSettings();
                          await _checkPermission();
                        }
                      }
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_songs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.music_note,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              context.tr('no_songs'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return _tabIndex == 0 ? _buildSongsList() : _buildPlaylistsView();
  }

  Widget _buildSongsList() {
    final visible = _filteredSongs;

    return Column(
      children: [
        AudioSearchField(
          query: _searchQuery,
          onChanged: (v) => setState(() => _searchQuery = v),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
            label: Text('${context.tr('play_all')} (${visible.length})'),
            onPressed: visible.isEmpty
                ? null
                : () async {
                    final idx = _songs.indexOf(visible.first);
                    if (idx >= 0) {
                      try {
                        await _service.playSong(idx);
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
        Expanded(
          child: ListenableBuilder(
            listenable: _service,
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
              final songIndex = _songs.indexOf(song);
              final isCurrent = _service.currentIndex == songIndex;
              return ListTile(
                leading: QueryArtworkWidget(
                  id: song.id,
                  type: ArtworkType.AUDIO,
                  nullArtworkWidget: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.15)
                          : Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.music_note,
                      color: isCurrent
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
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
                    color: isCurrent
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurface,
                  ),
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
                trailing: Text(
                  _fmt(Duration(milliseconds: song.duration ?? 0)),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                onTap: () async {
                  try {
                    await _service.togglePlayPauseFromIndex(songIndex);
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

  Widget _buildPlaylistsView() {
    if (_playlists.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.playlist_play,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              context.tr('no_playlists'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              icon: const Icon(Icons.add),
              label: Text(context.tr('create_playlist')),
              onPressed: _createPlaylist,
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: _playlists.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              icon: const Icon(Icons.add),
              label: Text(context.tr('create_playlist')),
              onPressed: _createPlaylist,
            ),
          );
        }
        final p = _playlists[index - 1];
        return ListTile(
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.playlist_play,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          title: Text(
            p.name,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text('${p.songPaths.length} ${context.tr('songs')}'),
          trailing: PopupMenuButton(
            itemBuilder: (_) => [
              PopupMenuItem(value: 'open', child: Text(context.tr('open'))),
              PopupMenuItem(value: 'delete', child: Text(context.tr('delete'))),
            ],
            onSelected: (v) async {
              if (v == 'delete') {
                setState(() => _playlists.removeAt(index - 1));
                await _savePlaylists();
              } else {
                _openPlaylist(index - 1);
              }
            },
          ),
          onTap: () => _openPlaylist(index - 1),
        );
      },
    );
  }

  void _openPlaylist(int idx) {
    final p = _playlists[idx];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PlaylistViewScreen(
          playlist: p,
          songs: _songs,
          onPlay: (songPaths, startIdx) =>
              _playPlaylistSongs(songPaths, startIdx),
          onRemove: (songPath) async {
            setState(
              () => _playlists[idx].songs.removeWhere((s) => s.path == songPath),
            );
            await _savePlaylists();
          },
        ),
      ),
    );
  }
}

class _PlaylistViewScreen extends StatelessWidget {
  final MusicPlaylist playlist;
  final List<SongModel> songs;
  final Function(List<String>, int) onPlay;
  final Function(String) onRemove;

  const _PlaylistViewScreen({
    required this.playlist,
    required this.songs,
    required this.onPlay,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final playlistSongs = playlist.songPaths
        .map((path) {
          final idx = songs.indexWhere((s) => s.data == path);
          return idx >= 0 ? songs[idx] : null;
        })
        .whereType<SongModel>()
        .toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          playlist.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: playlistSongs.isEmpty
          ? Center(
              child: Text(
                context.tr('no_songs_in_playlist'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: playlistSongs.length,
              itemBuilder: (context, index) {
                final song = playlistSongs[index];
                return ListTile(
                  leading: QueryArtworkWidget(
                    id: song.id,
                    type: ArtworkType.AUDIO,
                    nullArtworkWidget: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.music_note,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    artworkFit: BoxFit.cover,
                    artworkBorder: BorderRadius.circular(8),
                  ),
                  title: Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    song.artist ?? context.tr('unknown_artist'),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(
                      Icons.remove_circle_outline,
                      color: Colors.red,
                    ),
                    onPressed: () => onRemove(song.data),
                  ),
                  onTap: () => onPlay(playlist.songPaths, index),
                );
              },
            ),
    );
  }
}
