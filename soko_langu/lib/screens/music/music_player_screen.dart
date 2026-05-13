import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MusicPlaylist {
  final String name;
  final List<String> songPaths;

  MusicPlaylist({required this.name, required this.songPaths});

  Map<String, dynamic> toJson() => {'name': name, 'songPaths': songPaths};

  factory MusicPlaylist.fromJson(Map<String, dynamic> json) => MusicPlaylist(
    name: json['name'] as String,
    songPaths: List<String>.from(json['songPaths']),
  );
}

class MusicPlayerScreen extends StatefulWidget {
  const MusicPlayerScreen({super.key});

  @override
  State<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends State<MusicPlayerScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  final AudioPlayer _player = AudioPlayer();
  List<SongModel> _songs = [];
  List<MusicPlaylist> _playlists = [];
  bool _hasPermission = false;
  bool _isLoading = true;
  int? _currentIndex;
  bool _isPlaying = false;
  int _tabIndex = 0;
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() => setState(() => _tabIndex = _tabCtrl.index));
    _checkPermission();
    _loadPlaylists();
    _player.onPlayerComplete.listen((_) {
      setState(() => _isPlaying = false);
      _next();
    });
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
    _player.dispose();
    super.dispose();
  }

  Future<void> _checkPermission() async {
    final sdk = Platform.isAndroid
        ? int.tryParse(Platform.operatingSystemVersion.split(' ').last) ?? 0
        : 0;
    final perms = sdk >= 33
        ? [Permission.audio, Permission.manageExternalStorage]
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
    final songs = await _audioQuery.querySongs(
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );
    if (mounted) {
      setState(() {
        _songs = songs;
        _isLoading = false;
      });
      if (songs.isNotEmpty) _playSong(0);
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

  Future<void> _createPlaylist() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Playlist'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Playlist name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      setState(() => _playlists.add(MusicPlaylist(name: name, songPaths: [])));
      await _savePlaylists();
    }
  }

  Future<void> _addToPlaylist(int songIndex) async {
    final song = _songs[songIndex];
    if (song.data.isEmpty) return;
    final playlist = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Add to Playlist'),
        children: [
          ..._playlists.map(
            (p) => SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, p.name),
              child: Text(p.name),
            ),
          ),
          if (_playlists.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No playlists yet. Create one first.'),
            ),
        ],
      ),
    );
    if (playlist != null) {
      setState(() {
        final idx = _playlists.indexWhere((p) => p.name == playlist);
        if (idx >= 0 && !_playlists[idx].songPaths.contains(song.data)) {
          _playlists[idx].songPaths.add(song.data);
        }
      });
      await _savePlaylists();
    }
  }

  Future<void> _playSong(int index) async {
    if (index < 0 || index >= _songs.length) return;
    final song = _songs[index];
    if (song.data.isEmpty) return;
    setState(() {
      _currentIndex = index;
      _isPlaying = true;
    });
    await _player.stop();
    await _player.play(DeviceFileSource(song.data));
  }

  void _playPlaylistSongs(List<String> paths, int startIndex) {
    if (paths.isEmpty) return;
    final path = paths[startIndex];
    final idx = _songs.indexWhere((s) => s.data == path);
    if (idx >= 0) _playSong(idx);
  }

  void _togglePlayPause() {
    if (_currentIndex == null) return;
    if (_isPlaying) {
      _player.pause();
      setState(() => _isPlaying = false);
    } else {
      _player.resume();
      setState(() => _isPlaying = true);
    }
  }

  void _next() {
    if (_currentIndex == null || _songs.isEmpty) return;
    _playSong((_currentIndex! + 1) % _songs.length);
  }

  void _previous() {
    if (_currentIndex == null || _songs.isEmpty) return;
    _playSong((_currentIndex! - 1 + _songs.length) % _songs.length);
  }

  String _fmt(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Music Player',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: _hasPermission && _songs.isNotEmpty
            ? TabBar(
                controller: _tabCtrl,
                labelColor: Colors.green,
                unselectedLabelColor: Colors.grey,
                indicatorColor: Colors.green,
                tabs: const [
                  Tab(text: 'Songs'),
                  Tab(text: 'Playlists'),
                ],
              )
            : null,
      ),
      body: SafeArea(child: _buildBody()),
      bottomNavigationBar: _currentIndex != null ? _buildMiniPlayer() : null,
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

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
                  color: Colors.green.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.music_note_rounded,
                  size: 50,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                "Music Player",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                "To play your music, Soko Langu needs permission to access audio files on your device.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Tap 'Allow Access' to grant permission.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey[500]),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                  icon: const Icon(Icons.check_circle),
                  label: const Text(
                    "Allow Access",
                    style: TextStyle(fontSize: 16),
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
                        ? [Permission.audio, Permission.manageExternalStorage]
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
                            title: const Text("Permission Required"),
                            content: const Text(
                              "Permission was denied. Open app settings to enable it manually.",
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text("Cancel"),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text("Open Settings"),
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
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 20,
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.music_note, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text("No songs found", style: TextStyle(color: Colors.grey[600])),
            ],
          ),
        ),
      );
    }

    return _tabIndex == 0 ? _buildSongsList() : _buildPlaylistsView();
  }

  Widget _buildSongsList() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.playlist_play),
            label: Text("Play All (${_songs.length} songs)"),
            onPressed: () => _playSong(0),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: _songs.length,
            itemBuilder: (context, index) {
              final song = _songs[index];
              final isCurrent = _currentIndex == index;
              return ListTile(
                leading: QueryArtworkWidget(
                  id: song.id,
                  type: ArtworkType.AUDIO,
                  nullArtworkWidget: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? Colors.green.withValues(alpha: 0.15)
                          : Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.music_note,
                      color: isCurrent ? Colors.green : Colors.grey[500],
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
                    color: isCurrent ? Colors.green : Colors.black,
                  ),
                ),
                subtitle: Text(
                  song.artist ?? 'Unknown Artist',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                trailing: Text(
                  _fmt(Duration(milliseconds: song.duration ?? 0)),
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
                onTap: () => _playSong(index),
                onLongPress: () => _addToPlaylist(index),
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
            Icon(Icons.playlist_play, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text("No playlists yet", style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.add),
              label: const Text('Create Playlist'),
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
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.add),
              label: const Text('Create Playlist'),
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
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.playlist_play, color: Colors.green),
          ),
          title: Text(
            p.name,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text('${p.songPaths.length} songs'),
          trailing: PopupMenuButton(
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'open', child: Text('Open')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
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
            setState(() => _playlists[idx].songPaths.remove(songPath));
            await _savePlaylists();
          },
        ),
      ),
    );
  }

  Widget _buildMiniPlayer() {
    final song = _currentIndex != null && _currentIndex! < _songs.length
        ? _songs[_currentIndex!]
        : null;
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: Colors.green[50],
        border: Border(
          top: BorderSide(color: Colors.green.withValues(alpha: 0.2)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          if (song != null)
            QueryArtworkWidget(
              id: song.id,
              type: ArtworkType.AUDIO,
              nullArtworkWidget: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.music_note, color: Colors.grey[600]),
              ),
              artworkFit: BoxFit.cover,
              artworkBorder: BorderRadius.circular(8),
              size: 48,
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song?.title ?? '',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (song?.artist != null)
                  Text(
                    song!.artist!,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.skip_previous_rounded),
            onPressed: _previous,
          ),
          Container(
            decoration: const BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 24,
              ),
              onPressed: _togglePlayPause,
              padding: const EdgeInsets.all(8),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.skip_next_rounded),
            onPressed: _next,
          ),
        ],
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
                'No songs in this playlist',
                style: TextStyle(color: Colors.grey[600]),
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
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.music_note, color: Colors.grey[500]),
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
                    song.artist ?? 'Unknown',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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
