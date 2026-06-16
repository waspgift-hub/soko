import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/audio_player_service.dart';
import '../../services/smart_ad_service.dart';
import '../../shared/loading_widget.dart';
import '../../extensions/context_tr.dart';
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
  final SmartAdService _adService = SmartAdService();
  List<MusicPlaylist> _playlists = [];
  bool _hasAudioPermission = false;
  bool _isLoading = true;
  bool _adWatched = false;
  bool _showingAd = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAdAndLoad();
  }

  Future<void> _checkAdAndLoad() async {
    final prefs = await SharedPreferences.getInstance();
    final lastAdTime = prefs.getInt('media_ad_time') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - lastAdTime < 3600000) {
      setState(() => _adWatched = true);
      _loadMedia();
    } else {
      await _showRewardedAd();
    }
  }

  Future<void> _showRewardedAd() async {
    setState(() => _showingAd = true);
    await _adService.showRewardedAd(
      onUserEarned: () async {
        if (mounted) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt(
            'media_ad_time',
            DateTime.now().millisecondsSinceEpoch,
          );
        }
      },
    );
    if (mounted) {
      setState(() => _adWatched = true);
      _loadMedia();
      setState(() => _showingAd = false);
    }
  }

  void _loadMedia() {
    _loadPlaylists();
    _checkPermissions();
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
    final sdkVersion = int.tryParse(
      (await _getAndroidSdkVersion()).toString(),
    );
    final isAndroid13Plus = sdkVersion != null && sdkVersion >= 33;

    if (isAndroid13Plus) {
      final audioStatus = await Permission.audio.status;
      _hasAudioPermission = audioStatus.isGranted;
    } else {
      final storageStatus = await Permission.storage.status;
      _hasAudioPermission = storageStatus.isGranted;
    }

    if (_hasAudioPermission) {
      await _loadSongs();
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<int?> _getAndroidSdkVersion() async {
    if (Platform.isAndroid) {
      try {
        const channel = MethodChannel('soko_lang/device_info');
        return await channel.invokeMethod<int>('getSdkVersion');
      } catch (_) {}
    }
    return null;
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
        _audio.resetPlaylist();
        _audio.songs = songs;
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

  String _fmt(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  Widget _artworkWidget({required int songId, required double size, double radius = 8}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: QueryArtworkWidget(
        id: songId,
        type: ArtworkType.AUDIO,
        nullArtworkWidget: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          child: Icon(Icons.music_note, size: size * 0.5),
        ),
        quality: 75,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_adWatched) {
      return Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Theme.of(context).colorScheme.primary,
                Theme.of(context).colorScheme.secondary,
              ],
            ),
          ),
          child: Center(
            child: _showingAd
                ? const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 24),
                      Text(
                        'Loading Ad...',
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
                    ],
                  )
                : Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.play_circle_outline,
                          size: 100,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          context.tr('watch_ad_for_media'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          context.tr('watch_ad_for_media_desc'),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 48),
                        ElevatedButton.icon(
                          onPressed: _showRewardedAd,
                          icon: const Icon(Icons.play_arrow),
                          label: Text(context.tr('watch_ad_now')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor:
                                Theme.of(context).colorScheme.primary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 16,
                            ),
                            textStyle: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          context.tr('my_media'),
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: _buildBody(),
      bottomNavigationBar: StreamBuilder<int?>(
        stream: _audio.currentIndexStream,
        builder: (context, snap) {
          return snap.hasData ? _buildMiniPlayer() : const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return LoadingWidget(message: context.tr('loading'));
    if (!_hasAudioPermission) return _buildPermissionView();
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
          child: StreamBuilder<int?>(
            stream: _audio.currentIndexStream,
            builder: (context, indexSnap) {
              final currentIndex = indexSnap.data;
              return StreamBuilder<bool>(
                stream: _audio.playingStream,
                builder: (context, playingSnap) {
                  final isPlaying = playingSnap.data ?? false;
                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: _audio.songs.length,
                    itemBuilder: (context, index) {
                      final song = _audio.songs[index];
                      final isCurrent = currentIndex == index;
                      return ListTile(
                        leading: _artworkWidget(songId: song.id, size: 48),
                        title: Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                            color: isCurrent
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                        ),
                        subtitle: Text(
                          song.artist ?? context.tr('unknown_artist'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: isCurrent && isPlaying
                            ? Icon(Icons.equalizer, color: Theme.of(context).colorScheme.primary)
                            : null,
                        onTap: () => _audio.playSong(index),
                        onLongPress: () => _showSongOptions(index),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.music_off,
              size: 80,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 24),
            Text(
              context.tr('permission_storage_desc'),
              style: const TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _requestAudioPermission,
              icon: const Icon(Icons.security),
              label: Text(context.tr('grant_permission')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView(IconData icon, String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 24),
          Text(message, style: const TextStyle(fontSize: 18)),
        ],
      ),
    );
  }

  Widget _buildMiniPlayer() {
    return StreamBuilder<int?>(
      stream: _audio.currentIndexStream,
      builder: (context, indexSnap) {
        final songIndex = indexSnap.data;
        final song = songIndex != null && songIndex < _audio.songs.length
            ? _audio.songs[songIndex]
            : null;
        return StreamBuilder<bool>(
          stream: _audio.playingStream,
          builder: (context, playingSnap) {
            final isPlaying = playingSnap.data ?? false;
            return StreamBuilder<Duration>(
              stream: _audio.positionStream,
              builder: (context, posSnap) {
                final position = posSnap.data ?? Duration.zero;
                final duration = _audio.duration;
                final progress = duration.inMilliseconds > 0
                    ? position.inMilliseconds.toDouble() /
                        duration.inMilliseconds.toDouble()
                    : 0.0;

                return GestureDetector(
                  onVerticalDragDown: (_) => _showNowPlaying(),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LinearProgressIndicator(
                          value: progress,
                          backgroundColor:
                              Theme.of(context).colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                          leading: song != null
                              ? _artworkWidget(songId: song.id, size: 40)
                              : Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Icon(Icons.music_note, size: 20),
                                ),
                          title: Text(
                            song?.title ?? context.tr('no_song_playing'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            song?.artist ?? context.tr('unknown_artist'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.skip_previous),
                                onPressed: () => _audio.previous(),
                              ),
                              IconButton(
                                icon: Icon(
                                  isPlaying ? Icons.pause : Icons.play_arrow,
                                ),
                                onPressed: () => _audio.togglePlayPause(),
                              ),
                              IconButton(
                                icon: const Icon(Icons.skip_next),
                                onPressed: () => _audio.next(),
                              ),
                            ],
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
      },
    );
  }

  void _showNowPlaying() {
    final currentIndex = _audio.currentIndex;
    if (currentIndex == null) return;
    final song = _audio.songs[currentIndex];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: QueryArtworkWidget(
                    id: song.id,
                    type: ArtworkType.AUDIO,
                    nullArtworkWidget: Container(
                      width: 250,
                      height: 250,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      ),
                      child: Icon(Icons.music_note, size: 80),
                    ),
                    quality: 100,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  song.title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                Text(
                  song.artist ?? context.tr('unknown_artist'),
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                StreamBuilder<Duration>(
                  stream: _audio.positionStream,
                  builder: (ctx, snapshot) {
                    final pos = snapshot.data ?? Duration.zero;
                    return Column(
                      children: [
                        Slider(
                          value: pos.inMilliseconds.toDouble(),
                          max: _audio.duration.inMilliseconds.toDouble(),
                          onChanged: (v) {
                            _audio.seek(Duration(milliseconds: v.toInt()));
                          },
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_fmt(pos)),
                              Text(_fmt(_audio.duration)),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ValueListenableBuilder<bool>(
                      valueListenable: _audio.shuffleNotifier,
                      builder: (ctx, shuffle, _) => IconButton(
                        icon: Icon(
                          Icons.shuffle,
                          color: shuffle
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        onPressed: () => _audio.toggleShuffle(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_previous),
                      iconSize: 36,
                      onPressed: () => _audio.previous(),
                    ),
                    StreamBuilder<bool>(
                      stream: _audio.playingStream,
                      builder: (ctx, snap) {
                        final isPlaying = snap.data ?? false;
                        return IconButton(
                          icon: Icon(
                            isPlaying
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_filled,
                            size: 64,
                          ),
                          onPressed: () => _audio.togglePlayPause(),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next),
                      iconSize: 36,
                      onPressed: () => _audio.next(),
                    ),
                    ValueListenableBuilder<PlayerRepeatMode>(
                      valueListenable: _audio.repeatNotifier,
                      builder: (ctx, repeat, _) {
                        IconData repeatIcon;
                        if (repeat == PlayerRepeatMode.one) {
                          repeatIcon = Icons.repeat_one;
                        } else {
                          repeatIcon = Icons.repeat;
                        }
                        return IconButton(
                          icon: Icon(
                            repeatIcon,
                            color: repeat != PlayerRepeatMode.off
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                          onPressed: () => _audio.cycleRepeat(),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.stop, size: 32),
                      onPressed: () => _audio.stop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => _showAddToPlaylist(currentIndex),
                  icon: const Icon(Icons.playlist_add),
                  label: Text(context.tr('add_to_playlist')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSongOptions(int index) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: Text(context.tr('play_all')),
              onTap: () {
                Navigator.pop(ctx);
                _audio.playSong(index);
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: Text(context.tr('add_to_playlist')),
              onTap: () {
                Navigator.pop(ctx);
                _showAddToPlaylist(index);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAddToPlaylist(int songIndex) {
    final song = _audio.songs[songIndex];
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: Text(context.tr('new_playlist')),
              onTap: () {
                Navigator.pop(ctx);
                _showCreatePlaylistSheet(songIndex: songIndex);
              },
            ),
            const Divider(),
            ..._playlists.map(
              (p) => ListTile(
                leading: const Icon(Icons.queue_music),
                title: Text(p.name),
                subtitle: Text('${p.songs.length} songs'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    final exists = p.songs.any((s) => s.path == song.data);
                    if (!exists) {
                      p.songs.add(
                        PlaylistSong(
                          path: song.data,
                          title: song.title,
                          artist: song.artist,
                        ),
                      );
                    }
                  });
                  _savePlaylists();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreatePlaylistSheet({int? songIndex}) {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              decoration: InputDecoration(
                labelText: context.tr('playlist_name'),
                border: const OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                if (ctrl.text.trim().isEmpty) return;
                final songsList = <PlaylistSong>[];
                if (songIndex != null && songIndex < _audio.songs.length) {
                  final s = _audio.songs[songIndex];
                  songsList.add(
                    PlaylistSong(
                      path: s.data,
                      title: s.title,
                      artist: s.artist,
                    ),
                  );
                }
                setState(() {
                  _playlists.add(
                    MusicPlaylist(
                      name: ctrl.text.trim(),
                      songs: songsList,
                    ),
                  );
                });
                await _savePlaylists();
                if (mounted) Navigator.pop(ctx);
              },
              child: Text(context.tr('create')),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

