import 'package:flutter/material.dart';
import '../../extensions/context_tr.dart';
import '../../models/soko_media_item.dart';
import '../../services/media_library_service.dart';
import '../../services/media_player_service.dart';
import '../../widgets/media/media_item_tile.dart';
import './now_playing_screen.dart';
import './video_player_screen.dart';

/// Device-storage media library with a Muziki (audio) tab, a Video tab,
/// a search field for audio, and a file-picker import action in the AppBar.
class MediaLibraryScreen extends StatefulWidget {
  const MediaLibraryScreen({super.key});
  @override
  State<MediaLibraryScreen> createState() => _MediaLibraryScreenState();
}

class _MediaLibraryScreenState extends State<MediaLibraryScreen> {
  List<SokoMediaItem> _songs = const [];
  List<SokoMediaItem> _videos = const [];
  bool _loading = true;
  bool _permissionGranted = false;
  String _search = '';
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _permissionGranted = await MediaLibraryService.instance.requestPermission();
    await _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final musicFuture = MediaLibraryService.instance.scanMusic();
    final videoFuture = MediaLibraryService.instance.scanVideos();
    final results = await Future.wait([musicFuture, videoFuture]);
    if (!mounted) return;
    setState(() {
      _songs = results[0];
      _videos = results[1];
      _loading = false;
    });
  }

  List<SokoMediaItem> get _filteredSongs {
    final q = _search.toLowerCase().trim();
    if (q.isEmpty) return _songs;
    return _songs
        .where((s) =>
            s.title.toLowerCase().contains(q) ||
            (s.artist?.toLowerCase().contains(q) ?? false) ||
            (s.album?.toLowerCase().contains(q) ?? false))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(context.tr('media_library')),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: context.tr('import_files'),
            onPressed: _importFiles,
          ),
        ],
      ),
      body: !_permissionGranted
          ? _buildPermissionDenied(cs)
          : DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  Material(
                    color: cs.surface,
                    child: TabBar(
                      onTap: (i) => setState(() => _tab = i),
                      labelColor: cs.onSurface,
                      unselectedLabelColor: cs.onSurfaceVariant,
                      indicatorColor: cs.onSurface,
                      labelStyle: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                      unselectedLabelStyle: const TextStyle(fontSize: 13),
                      tabs: [
                        Tab(text: context.tr('music')),
                        Tab(text: context.tr('videos')),
                      ],
                    ),
                  ),
                  if (_tab == 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: TextField(
                        onChanged: (v) => setState(() => _search = v),
                        decoration: InputDecoration(
                          hintText: context.tr('search'),
                          hintStyle: TextStyle(
                            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                          prefixIcon: Icon(Icons.search,
                              color: cs.onSurfaceVariant, size: 20),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: cs.outline),
                          ),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        style: TextStyle(color: cs.onSurface, fontSize: 13),
                      ),
                    ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _refresh,
                      child: _loading
                          ? const Center(child: CircularProgressIndicator())
                          : _tab == 0
                              ? _buildSongList(cs)
                              : _buildVideoList(cs),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSongList(ColorScheme cs) {
    final items = _filteredSongs;
    if (items.isEmpty) return _emptyState(cs, context.tr('no_media'));
    final player = MediaPlayerService.instance;
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        final active = player.current?.id == item.id;
        return MediaItemTile(
          item: item,
          active: active,
          onTap: () async {
            await player.playQueue(items, startIndex: i);
            if (context.mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const NowPlayingScreen(),
                ),
              );
            }
          },
        );
      },
    );
  }

  Widget _buildVideoList(ColorScheme cs) {
    final items = _videos;
    if (items.isEmpty) return _emptyState(cs, context.tr('no_media'));
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        return MediaItemTile(
          item: item,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => VideoPlayerScreen(item: item)),
            );
          },
        );
      },
    );
  }

  Widget _emptyState(ColorScheme cs, String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_off_rounded,
                size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(
              msg,
              style: TextStyle(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionDenied(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline,
                size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(
              context.tr('permission_required'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('permission_media_desc'),
              style: TextStyle(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _init,
              child: Text(context.tr('allow_access')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importFiles() async {
    final items = await MediaLibraryService.instance.importFiles();
    if (!mounted || items.isEmpty) return;
    final player = MediaPlayerService.instance;
    await player.playQueue(items);
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const NowPlayingScreen()),
      );
    }
  }
}