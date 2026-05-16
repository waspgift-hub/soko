import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
// ignore: unused_import
import 'package:video_player/video_player.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/video_query_service.dart';
import '../../services/audio_player_service.dart';
import '../../shared/loading_widget.dart';
import '../../extensions/context_tr.dart';
import '../../models/music_playlist.dart';

class LocalVideoFile {
  final String path;
  final String name;
  final int durationMs;
  final int sizeBytes;
  final String contentUri;
  LocalVideoFile({
    required this.path,
    required this.name,
    this.durationMs = 0,
    this.sizeBytes = 0,
    this.contentUri = '',
  });
}

class MediaPlayerScreen extends StatefulWidget {
  const MediaPlayerScreen({super.key});
  @override
  State<MediaPlayerScreen> createState() => _MediaPlayerScreenState();
}

class _MediaPlayerScreenState extends State<MediaPlayerScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  final AudioPlayerService _audio = AudioPlayerService.instance;
  List<LocalVideoFile> _videos = [];
  List<MusicPlaylist> _playlists = [];
  bool _hasAudioPermission = false;
  bool _hasVideoPermission = false;
  bool _isLoading = true;
  late TabController _tabCtrl;

  VideoPlayerController? _videoController;
  String? _currentVideoPath;
  bool _isVideoPlaying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() => setState(() {}));
    _checkPermissions();
    _loadPlaylists();
    _audio.playbackState.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_hasAudioPermission || !_hasVideoPermission) _checkPermissions();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabCtrl.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    if (!Platform.isAndroid) {
      return setState(() => _isLoading = false);
    }
    for (final p in [
      Permission.audio,
      Permission.photos,
      Permission.videos,
      Permission.storage,
    ]) {
      if (await p.status.isGranted) {
        if (p == Permission.audio ||
            p == Permission.photos ||
            p == Permission.storage) {
          _hasAudioPermission = true;
        }
        if (p == Permission.videos ||
            p == Permission.photos ||
            p == Permission.storage) {
          _hasVideoPermission = true;
        }
      }
    }
    final futures = <Future>[];
    if (_hasAudioPermission) futures.add(_loadSongs());
    if (_hasVideoPermission) futures.add(_loadVideos());
    if (futures.isNotEmpty) await Future.wait(futures);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _requestAudioPermission() async {
    setState(() => _isLoading = true);
    for (final p in [Permission.audio, Permission.photos, Permission.storage]) {
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

  Future<void> _requestVideoPermission() async {
    setState(() => _isLoading = true);
    for (final p in [
      Permission.videos,
      Permission.photos,
      Permission.storage,
    ]) {
      if (await p.request().isGranted) {
        setState(() => _hasVideoPermission = true);
        await _loadVideos();
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
      setState(() {
        _audio.songs = songs;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadVideos() async {
    final results = await VideoQueryService.queryVideos();
    if (mounted) {
      setState(() {
        _videos = results
            .map(
              (v) => LocalVideoFile(
                path: v['data'] as String? ?? '',
                name: v['displayName'] as String? ?? 'Unknown',
                durationMs: (v['duration'] as num?)?.toInt() ?? 0,
                sizeBytes: (v['size'] as num?)?.toInt() ?? 0,
                contentUri: v['contentUri'] as String? ?? '',
              ),
            )
            .toList();
        _isLoading = false;
      });
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

  void _disposeVideo() {
    _videoController?.dispose();
    _videoController = null;
    _currentVideoPath = null;
    _isVideoPlaying = false;
  }

  Future<void> _playVideo(LocalVideoFile video) async {
    if (_audio.currentIndex != null) {
      await _audio.stop();
      _audio.currentIndex = null;
    }
    _disposeVideo();
    final VideoPlayerController ctrl;
    if (video.path.isNotEmpty) {
      ctrl = VideoPlayerController.file(File(video.path));
    } else if (video.contentUri.isNotEmpty) {
      ctrl = VideoPlayerController.networkUrl(Uri.parse(video.contentUri));
    } else {
      return;
    }
    await ctrl.initialize();
    if (mounted) {
      setState(() {
        _videoController = ctrl;
        _currentVideoPath = video.path;
        _isVideoPlaying = true;
      });
      ctrl.play();
      ctrl.addListener(() {
        if (mounted && ctrl.value.isCompleted) {
          setState(() => _isVideoPlaying = false);
        }
      });
    }
  }

  String _fmt(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  void _openFullPlayer() {
    if (_audio.currentIndex == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullPlayerPage(
          playlists: _playlists,
          onAddToPlaylist: _addCurrentToPlaylist,
        ),
      ),
    );
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
        if (idx >= 0 && !_playlists[idx].songPaths.contains(song.data)) {
          _playlists[idx].songPaths.add(song.data);
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
        if (idx >= 0 && !_playlists[idx].songPaths.contains(song.data)) {
          _playlists[idx].songPaths.add(song.data);
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller: _tabCtrl,
                  labelColor: Theme.of(context).colorScheme.primary,
                  unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
                  indicatorColor: Theme.of(context).colorScheme.primary,
                  tabs: [
                    Tab(
                      icon: const Icon(Icons.music_note, size: 20),
                      text: context.tr('audio'),
                    ),
                    Tab(
                      icon: const Icon(Icons.videocam, size: 20),
                      text: context.tr('video'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      body: _buildBody(),
      bottomNavigationBar: _tabCtrl.index == 0 && _audio.currentIndex != null
          ? _buildMiniPlayer()
          : null,
    );
  }

  Widget _buildBody() {
    if (_isLoading) return LoadingWidget(message: context.tr('loading'));
    if (_tabCtrl.index == 0) return _buildAudioTab();
    return _buildVideoTab();
  }

  // ─── AUDIO TAB ───────────────────────────────────────────────
  Widget _buildAudioTab() {
    if (!_hasAudioPermission) return _buildPermissionView(true);
    if (_audio.songs.isEmpty) {
      return _buildEmptyView(Icons.music_note, context.tr('no_songs'));
    }
    return Column(
      children: [
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
                    '${context.tr('play_all')} (${_audio.songs.length} songs)',
                    style: const TextStyle(fontSize: 14),
                  ),
                  onPressed: () => _audio.playSong(0),
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
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: _audio.songs.length,
            itemBuilder: (context, index) {
              final song = _audio.songs[index];
              final isCurrent = _audio.currentIndex == index;
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
                onTap: () => _audio.playSong(index),
                onLongPress: () => _addToPlaylist(index),
              );
            },
          ),
        ),
      ],
    );
  }

  // ─── VIDEO TAB ───────────────────────────────────────────────
  Widget _buildVideoTab() {
    if (!_hasVideoPermission) return _buildPermissionView(false);
    if (_videos.isEmpty) {
      return _buildEmptyView(Icons.videocam, context.tr('no_videos'));
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                '${_videos.length} ${context.tr('videos')}',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Expanded(child: _buildVideoGrid()),
        if (_currentVideoPath != null) _buildVideoMiniPlayer(),
      ],
    );
  }

  Widget _buildVideoGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 0.7,
      ),
      itemCount: _videos.length,
      itemBuilder: (context, index) => _videoGridTile(_videos[index]),
    );
  }

  Widget _videoGridTile(LocalVideoFile video) {
    return GestureDetector(
      onTap: () => _playVideo(video),
      child: Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: Colors.black26,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
            if (video.durationMs > 0)
              Positioned(
                right: 4,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _fmt(Duration(milliseconds: video.durationMs)),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─── PERMISSION VIEW ─────────────────────────────────────────
  Widget _buildPermissionView(bool isAudio) {
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
                  isAudio ? Icons.music_note_rounded : Icons.videocam_rounded,
                  size: 50,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                isAudio ? 'Audio Player' : 'Video Player',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                isAudio
                    ? 'Allow access to your music files to play audio.'
                    : 'Allow access to your video files to play videos.',
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
                  onPressed: isAudio
                      ? _requestAudioPermission
                      : _requestVideoPermission,
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

  // ─── VIDEO MINI PLAYER ────────────────────────────────────────
  Widget _buildVideoMiniPlayer() {
    final ctrl = _videoController;
    if (ctrl == null || !ctrl.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return GestureDetector(
      onTap: _openFullVideoPlayer,
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: Colors.black,
          border: Border(top: BorderSide(color: Theme.of(context).colorScheme.primary.withAlpha(80))),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 80,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  VideoPlayer(ctrl),
                  Icon(
                    _isVideoPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white54,
                    size: 28,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _currentVideoPath != null
                    ? _videos
                          .firstWhere(
                            (v) => v.path == _currentVideoPath,
                            orElse: () =>
                                LocalVideoFile(path: '', name: 'Video'),
                          )
                          .name
                    : 'Video',
                style: const TextStyle(color: Colors.white, fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(
                Icons.skip_previous_rounded,
                color: Colors.white,
              ),
              onPressed: () => setState(() {
                final pos = ctrl.value.position - const Duration(seconds: 10);
                ctrl.seekTo(Duration(seconds: max(0, pos.inSeconds)));
              }),
            ),
            Container(
              decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.primary,
            ),
            child: IconButton(
              icon: Icon(
                _isVideoPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: () {
                  setState(() {
                    ctrl.value.isPlaying ? ctrl.pause() : ctrl.play();
                    _isVideoPlaying = ctrl.value.isPlaying;
                  });
                },
                padding: const EdgeInsets.all(6),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
              onPressed: () => setState(() {
                final pos = ctrl.value.position + const Duration(seconds: 10);
                ctrl.seekTo(
                  Duration(
                    seconds: min(pos.inSeconds, ctrl.value.duration.inSeconds),
                  ),
                );
              }),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white70, size: 20),
              onPressed: () {
                _disposeVideo();
                setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openFullVideoPlayer() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullVideoPage(
          controller: _videoController!,
          isPlaying: _isVideoPlaying,
          onClose: () {
            _disposeVideo();
            setState(() {});
          },
        ),
      ),
    );
  }

  // ─── MINI PLAYER (AUDIO) ─────────────────────────────────────
  Widget _buildMiniPlayer() {
    final song =
        _audio.currentIndex != null &&
            _audio.currentIndex! < _audio.songs.length
        ? _audio.songs[_audio.currentIndex!]
        : null;
    return GestureDetector(
      onTap: _openFullPlayer,
      child: Container(
        height: 72,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          border: Border(top: BorderSide(color: Theme.of(context).colorScheme.primary.withAlpha(40))),
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
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.music_note, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.skip_previous_rounded),
              onPressed: _audio.previous,
            ),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(
                  _audio.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: Theme.of(context).colorScheme.onPrimary,
                  size: 24,
                ),
                onPressed: _audio.togglePlayPause,
                padding: const EdgeInsets.all(8),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.skip_next_rounded),
              onPressed: _audio.next,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── FULL VIDEO PLAYER PAGE ───────────────────────────────────
class _FullVideoPage extends StatefulWidget {
  final VideoPlayerController controller;
  final bool isPlaying;
  final VoidCallback onClose;

  const _FullVideoPage({
    required this.controller,
    required this.isPlaying,
    required this.onClose,
  });

  @override
  State<_FullVideoPage> createState() => _FullVideoPageState();
}

class _FullVideoPageState extends State<_FullVideoPage> {
  late VideoPlayerController _ctrl;
  late bool _isPlaying;

  @override
  void initState() {
    super.initState();
    _ctrl = widget.controller;
    _isPlaying = widget.isPlaying;
    _ctrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() {
                  _ctrl.value.isPlaying ? _ctrl.pause() : _ctrl.play();
                  _isPlaying = _ctrl.value.isPlaying;
                }),
                child: Center(
                  child: _ctrl.value.isInitialized
                      ? AspectRatio(
                          aspectRatio: _ctrl.value.aspectRatio,
                          child: VideoPlayer(_ctrl),
                        )
                      : const CircularProgressIndicator(),
                ),
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.of(context).padding.bottom,
              ),
              color: Colors.black,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        _fmt(_ctrl.value.position),
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderThemeData(
                            activeTrackColor: Theme.of(context).colorScheme.primary,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: Theme.of(context).colorScheme.primary,
                            trackHeight: 3,
                          ),
                          child: Slider(
                            value: _ctrl.value.isInitialized
                                ? _ctrl.value.position.inMilliseconds
                                      .toDouble()
                                      .clamp(
                                        0,
                                        _ctrl.value.duration.inMilliseconds
                                            .toDouble(),
                                      )
                                : 0,
                            max: _ctrl.value.isInitialized
                                ? _ctrl.value.duration.inMilliseconds.toDouble()
                                : 1,
                            onChanged: (v) =>
                                _ctrl.seekTo(Duration(milliseconds: v.toInt())),
                          ),
                        ),
                      ),
                      Text(
                        _fmt(_ctrl.value.duration),
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.replay_10,
                          color: Colors.white,
                          size: 32,
                        ),
                        onPressed: () {
                          final pos =
                              _ctrl.value.position -
                              const Duration(seconds: 10);
                          _ctrl.seekTo(
                            Duration(seconds: max(0, pos.inSeconds)),
                          );
                        },
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: Icon(
                            _isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 40,
                          ),
                          onPressed: () {
                            setState(() {
                              _ctrl.value.isPlaying
                                  ? _ctrl.pause()
                                  : _ctrl.play();
                              _isPlaying = _ctrl.value.isPlaying;
                            });
                          },
                          padding: const EdgeInsets.all(16),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.forward_10,
                          color: Colors.white,
                          size: 32,
                        ),
                        onPressed: () {
                          final pos =
                              _ctrl.value.position +
                              const Duration(seconds: 10);
                          _ctrl.seekTo(
                            Duration(
                              seconds: min(
                                pos.inSeconds,
                                _ctrl.value.duration.inSeconds,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

// ─── FULL PLAYER PAGE (Modern Glassmorphism) ──────────────────
class _FullPlayerPage extends StatefulWidget {
  final List<MusicPlaylist> playlists;
  final VoidCallback onAddToPlaylist;

  const _FullPlayerPage({
    required this.playlists,
    required this.onAddToPlaylist,
  });

  @override
  State<_FullPlayerPage> createState() => _FullPlayerPageState();
}

class _FullPlayerPageState extends State<_FullPlayerPage> {
  final AudioPlayerService _audio = AudioPlayerService.instance;
  bool _isSliding = false;
  double _slidingValue = 0;

  void _openPlaylistPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _NowPlayingList(
          songs: _audio.songs,
          currentIndex: _audio.currentIndex ?? 0,
          onPlay: (i) {
            _audio.playSong(i);
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_audio.currentIndex == null || _audio.songs.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            context.tr('now_playing'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.music_note_rounded, size: 80, color: Theme.of(context).colorScheme.surfaceContainerHighest),
              const SizedBox(height: 16),
              Text(
                context.tr('no_song_playing'),
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    final song = _audio.songs[_audio.currentIndex!];
    final pos = _isSliding
        ? Duration(milliseconds: _slidingValue.toInt())
        : _audio.position;
    final dur = _audio.duration;
    final double albumArtSize = min(
      280.0,
      MediaQuery.of(context).size.shortestSide * 0.65,
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 4,
                left: 4,
                right: 4,
                bottom: 4,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.keyboard_arrow_down,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  Text(
                    context.tr('now_playing'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      Icons.playlist_play,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    onPressed: _openPlaylistPage,
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  32,
                  0,
                  32,
                  MediaQuery.of(context).padding.bottom + 20,
                ),
                child: Column(
                  children: [
                    const Spacer(flex: 1),
                    // Album art with glow
                    Hero(
                      tag: 'player_art_${song.id}',
                      child: Container(
                        width: albumArtSize,
                        height: albumArtSize,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(32),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF2D6A4F,
                              ).withValues(alpha: 0.3),
                              blurRadius: 40,
                              spreadRadius: 8,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(32),
                          child: QueryArtworkWidget(
                            id: song.id,
                            type: ArtworkType.AUDIO,
                            nullArtworkWidget: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    const Color(
                                      0xFF2D6A4F,
                                    ).withValues(alpha: 0.3),
                                    const Color(
                                      0xFF40916C,
                                    ).withValues(alpha: 0.1),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(32),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.music_note_rounded,
                                    size: 80,
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                                  ),
                                  const SizedBox(height: 8),
                                  Icon(
                                    Icons.headphones_rounded,
                                    size: 32,
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.15),
                                  ),
                                ],
                              ),
                            ),
                            artworkFit: BoxFit.contain,
                            artworkBorder: BorderRadius.circular(32),
                            size: albumArtSize.round(),
                          ),
                        ),
                      ),
                    ),
                    const Spacer(flex: 1),

                    // Song info
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                song.title,
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                song.artist ?? context.tr('unknown_artist'),
                                style: TextStyle(
                                  fontSize: 15,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.playlist_add,
                            color: Theme.of(context).colorScheme.secondary,
                            size: 28,
                          ),
                          onPressed: widget.onAddToPlaylist,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Seek bar
                    _buildSeekBar(pos, dur),
                    const SizedBox(height: 20),

                    // Controls
                    _buildControls(),

                    const Spacer(flex: 1),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeekBar(Duration pos, Duration dur) {
    final progress = dur.inMilliseconds > 0
        ? pos.inMilliseconds / dur.inMilliseconds
        : 0.0;

    return Column(
      children: [
        GestureDetector(
          onTapDown: (details) {
            final box = context.findRenderObject() as RenderBox;
            final w = box.size.width - 64;
            final ratio = ((details.localPosition.dx - 32) / w).clamp(0.0, 1.0);
            final seekTo = (dur.inMilliseconds * ratio).toInt();
            _audio.seek(Duration(milliseconds: seekTo));
          },
          child: Container(
            height: 24,
            alignment: Alignment.center,
            child: Stack(
              children: [
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: progress.clamp(0.0, 1.0),
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left:
                      (MediaQuery.of(context).size.width - 64) *
                          progress.clamp(0.0, 1.0) -
                      6,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.6),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _fmt(pos),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
            ),
            Text(
              _fmt(dur),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Shuffle
          IconButton(
            icon: Icon(
              Icons.shuffle,
              color: _audio.shuffle
                  ? Theme.of(context).colorScheme.secondary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              size: 24,
            ),
            onPressed: () => setState(() => _audio.toggleShuffle()),
          ),
          // Previous
          IconButton(
            icon: Icon(
              Icons.skip_previous_rounded,
              color: Theme.of(context).colorScheme.secondary,
              size: 32,
            ),
            onPressed: () => setState(() => _audio.previous()),
            splashRadius: 20,
          ),
          // Play/Pause
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Theme.of(context).colorScheme.secondary, Theme.of(context).colorScheme.secondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: IconButton(
              icon: Icon(
                _audio.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: Colors.white,
              ),
              iconSize: 36,
              onPressed: () => setState(() => _audio.togglePlayPause()),
              padding: EdgeInsets.zero,
            ),
          ),
          // Next
          IconButton(
            icon: Icon(
              Icons.skip_next_rounded,
              color: Theme.of(context).colorScheme.secondary,
              size: 32,
            ),
            onPressed: () => setState(() => _audio.next()),
            splashRadius: 20,
          ),
          // Repeat
          IconButton(
            icon: _buildRepeatIcon(),
            onPressed: () => setState(() => _audio.cycleRepeat()),
          ),
        ],
      ),
    );
  }

  Widget _buildRepeatIcon() {
    switch (_audio.repeatMode) {
      case PlayerRepeatMode.off:
        return Icon(Icons.repeat, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 24);
      case PlayerRepeatMode.all:
        return Icon(Icons.repeat, color: Theme.of(context).colorScheme.secondary, size: 24);
      case PlayerRepeatMode.one:
        return Stack(
          alignment: Alignment.center,
          children: [
            Icon(Icons.repeat, color: Theme.of(context).colorScheme.secondary, size: 24),
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '1',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.secondary,
                    fontSize: 7,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        );
    }
  }

  String _fmt(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

class _NowPlayingList extends StatelessWidget {
  final List<SongModel> songs;
  final int currentIndex;
  final ValueChanged<int> onPlay;

  const _NowPlayingList({
    required this.songs,
    required this.currentIndex,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          context.tr('now_playing'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView.builder(
        itemCount: songs.length,
        itemBuilder: (context, index) {
          final song = songs[index];
          final isCurrent = index == currentIndex;
          return ListTile(
            leading: QueryArtworkWidget(
              id: song.id,
              type: ArtworkType.AUDIO,
              nullArtworkWidget: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isCurrent
                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
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
            trailing: isCurrent
                ? Icon(Icons.music_note, color: Theme.of(context).colorScheme.primary, size: 20)
                : null,
            onTap: isCurrent
                ? null
                : () {
                    onPlay(index);
                  },
          );
        },
      ),
    );
  }
}
