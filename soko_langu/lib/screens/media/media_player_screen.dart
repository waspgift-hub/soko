import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:video_player/video_player.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/video_query_service.dart';

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

class LocalVideoFile {
  final String path;
  final String name;
  final int durationMs;
  final int sizeBytes;
  LocalVideoFile({
    required this.path,
    required this.name,
    this.durationMs = 0,
    this.sizeBytes = 0,
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
  final AudioPlayer _player = AudioPlayer();
  List<SongModel> _songs = [];
  List<LocalVideoFile> _videos = [];
  List<MusicPlaylist> _playlists = [];
  bool _hasAudioPermission = false;
  bool _hasVideoPermission = false;
  bool _isLoading = true;
  int? _currentSongIndex;
  bool _isPlaying = false;
  late TabController _tabCtrl;

  VideoPlayerController? _videoController;
  String? _currentVideoPath;
  bool _isVideoPlaying = false;
  bool _showVideoGrid = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() => setState(() {}));
    _checkPermissions();
    _loadPlaylists();
    _player.onPlayerComplete.listen((_) {
      setState(() => _isPlaying = false);
      _next();
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
    _player.dispose();
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
    if (_hasAudioPermission) _loadSongs();
    if (_hasVideoPermission) _loadVideos();
    setState(() => _isLoading = false);
  }

  Future<void> _requestAudioPermission() async {
    setState(() => _isLoading = true);
    for (final p in [Permission.audio, Permission.photos, Permission.storage]) {
      if (await p.request().isGranted) {
        setState(() => _hasAudioPermission = true);
        _loadSongs();
        return;
      }
    }
    if (mounted) await _handleDenied();
    setState(() => _isLoading = false);
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
        _loadVideos();
        return;
      }
    }
    if (mounted) await _handleDenied();
    setState(() => _isLoading = false);
  }

  Future<void> _handleDenied() async {
    if (!mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permission Required'),
        content: const Text(
          'Permission was denied. Open app settings to enable it manually.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Open Settings'),
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
        _songs = songs;
        _isLoading = false;
      });
      if (songs.isNotEmpty && _currentSongIndex == null) _playSong(0);
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

  Future<void> _playSong(int index) async {
    if (index < 0 || index >= _songs.length) return;
    final song = _songs[index];
    if (song.data.isEmpty) return;
    _disposeVideo();
    setState(() {
      _currentSongIndex = index;
      _isPlaying = true;
    });
    await _player.stop();
    await _player.play(DeviceFileSource(song.data));
  }

  void _togglePlayPause() {
    if (_currentSongIndex == null) return;
    if (_isPlaying) {
      _player.pause();
      setState(() => _isPlaying = false);
    } else {
      _player.resume();
      setState(() => _isPlaying = true);
    }
  }

  void _next() {
    if (_currentSongIndex == null || _songs.isEmpty) return;
    _playSong((_currentSongIndex! + 1) % _songs.length);
  }

  void _previous() {
    if (_currentSongIndex == null || _songs.isEmpty) return;
    _playSong((_currentSongIndex! - 1 + _songs.length) % _songs.length);
  }

  void _disposeVideo() {
    _videoController?.dispose();
    _videoController = null;
    _currentVideoPath = null;
    _isVideoPlaying = false;
  }

  Future<void> _playVideo(LocalVideoFile video) async {
    if (_currentSongIndex != null) {
      await _player.stop();
      setState(() => _currentSongIndex = null);
    }
    _disposeVideo();
    final ctrl = VideoPlayerController.file(File(video.path));
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

  String _fmtFileSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'My Media',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: _hasAudioPermission && _hasVideoPermission
            ? TabBar(
                controller: _tabCtrl,
                labelColor: Colors.green,
                unselectedLabelColor: Colors.grey,
                indicatorColor: Colors.green,
                tabs: [
                  Tab(
                    icon: const Icon(Icons.music_note, size: 20),
                    text: 'Audio',
                  ),
                  Tab(
                    icon: const Icon(Icons.videocam, size: 20),
                    text: 'Video',
                  ),
                ],
              )
            : null,
      ),
      body: _buildBody(),
      bottomNavigationBar: _tabCtrl.index == 0 && _currentSongIndex != null
          ? _buildMiniPlayer()
          : null,
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_tabCtrl.index == 0) return _buildAudioTab();
    return _buildVideoTab();
  }

  // ─── AUDIO TAB ───────────────────────────────────────────────
  Widget _buildAudioTab() {
    if (!_hasAudioPermission) return _buildPermissionView(true);
    if (_songs.isEmpty) {
      return _buildEmptyView(Icons.music_note, 'No songs found');
    }
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
            label: Text('Play All (${_songs.length} songs)'),
            onPressed: () => _playSong(0),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: _songs.length,
            itemBuilder: (context, index) {
              final song = _songs[index];
              final isCurrent = _currentSongIndex == index;
              return ListTile(
                leading: QueryArtworkWidget(
                  id: song.id,
                  type: ArtworkType.AUDIO,
                  nullArtworkWidget: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? Colors.green.withAlpha(25)
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
              child: Text('No playlists yet.'),
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

  // ─── VIDEO TAB ───────────────────────────────────────────────
  Widget _buildVideoTab() {
    if (!_hasVideoPermission) return _buildPermissionView(false);
    if (_videos.isEmpty) {
      return _buildEmptyView(Icons.videocam, 'No videos found');
    }

    if (_currentVideoPath != null) return _buildVideoPlayer();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                '${_videos.length} videos',
                style: TextStyle(color: Colors.grey[600]),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(
                  _showVideoGrid ? Icons.list : Icons.grid_view,
                  color: Colors.green,
                ),
                onPressed: () =>
                    setState(() => _showVideoGrid = !_showVideoGrid),
              ),
            ],
          ),
        ),
        Expanded(child: _showVideoGrid ? _buildVideoGrid() : _buildVideoList()),
      ],
    );
  }

  Widget _buildVideoGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.8,
      ),
      itemCount: _videos.length,
      itemBuilder: (context, index) => _videoGridTile(_videos[index], index),
    );
  }

  Widget _videoGridTile(LocalVideoFile video, int index) {
    return GestureDetector(
      onTap: () => _playVideo(video),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                ),
                child: Center(
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.green.withAlpha(180),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    _fmtFileSize(video.sizeBytes),
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoList() {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: _videos.length,
      itemBuilder: (context, index) {
        final video = _videos[index];
        return ListTile(
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.videocam, color: Colors.green),
          ),
          title: Text(video.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            _fmtFileSize(video.sizeBytes),
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          trailing: const Icon(Icons.play_circle_fill, color: Colors.green),
          onTap: () => _playVideo(video),
        );
      },
    );
  }

  Widget _buildVideoPlayer() {
    final ctrl = _videoController;
    if (ctrl == null || !ctrl.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() {
                ctrl.value.isPlaying ? ctrl.pause() : ctrl.play();
                _isVideoPlaying = ctrl.value.isPlaying;
              });
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                VideoPlayer(ctrl),
                Center(
                  child: !_isVideoPlaying
                      ? Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: Colors.black45,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow,
                            color: Colors.white,
                            size: 40,
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
        _buildVideoControls(ctrl),
      ],
    );
  }

  Widget _buildVideoControls(VideoPlayerController ctrl) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                _fmt(ctrl.value.position),
                style: const TextStyle(fontSize: 12),
              ),
              Expanded(
                child: Slider(
                  value: ctrl.value.isInitialized
                      ? ctrl.value.position.inMilliseconds.toDouble().clamp(
                          0,
                          ctrl.value.duration.inMilliseconds.toDouble(),
                        )
                      : 0,
                  max: ctrl.value.isInitialized
                      ? ctrl.value.duration.inMilliseconds.toDouble()
                      : 1,
                  onChanged: (v) =>
                      ctrl.seekTo(Duration(milliseconds: v.toInt())),
                ),
              ),
              Text(
                _fmt(ctrl.value.duration),
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.fullscreen),
                onPressed: () => _enterFullScreen(ctrl),
              ),
              IconButton(
                icon: const Icon(Icons.replay_10),
                onPressed: () {
                  final pos = ctrl.value.position - const Duration(seconds: 10);
                  ctrl.seekTo(Duration(seconds: max(0, pos.inSeconds)));
                },
              ),
              IconButton(
                iconSize: 48,
                icon: Icon(
                  _isVideoPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled,
                  color: Colors.green,
                ),
                onPressed: () {
                  setState(() {
                    ctrl.value.isPlaying ? ctrl.pause() : ctrl.play();
                    _isVideoPlaying = ctrl.value.isPlaying;
                  });
                },
              ),
              IconButton(
                icon: const Icon(Icons.forward_10),
                onPressed: () {
                  final pos = ctrl.value.position + const Duration(seconds: 10);
                  ctrl.seekTo(
                    Duration(
                      seconds: min(
                        pos.inSeconds,
                        ctrl.value.duration.inSeconds,
                      ),
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  _disposeVideo();
                  setState(() {});
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _enterFullScreen(VideoPlayerController ctrl) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: GestureDetector(
              onTap: () {
                setState(
                  () => ctrl.value.isPlaying ? ctrl.pause() : ctrl.play(),
                );
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(child: VideoPlayer(ctrl)),
                  if (!ctrl.value.isPlaying)
                    const Icon(Icons.play_arrow, color: Colors.white, size: 64),
                  Positioned(
                    top: 40,
                    right: 16,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── PERMISSION VIEW ─────────────────────────────────────────
  Widget _buildPermissionView(bool isAudio) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.green.withAlpha(15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isAudio ? Icons.music_note_rounded : Icons.videocam_rounded,
              size: 50,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            isAudio ? 'Audio Player' : 'Video Player',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            isAudio
                ? 'Allow access to your music files to play audio.'
                : 'Allow access to your video files to play videos.',
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
              label: const Text("Allow Access", style: TextStyle(fontSize: 16)),
              onPressed: isAudio
                  ? _requestAudioPermission
                  : _requestVideoPermission,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView(IconData icon, String msg) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(msg, style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    );
  }

  // ─── MINI PLAYER ─────────────────────────────────────────────
  Widget _buildMiniPlayer() {
    final song = _currentSongIndex != null && _currentSongIndex! < _songs.length
        ? _songs[_currentSongIndex!]
        : null;
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: Colors.green[50],
        border: Border(top: BorderSide(color: Colors.green.withAlpha(40))),
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
