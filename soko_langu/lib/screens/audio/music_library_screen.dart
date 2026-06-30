import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../extensions/context_tr.dart';
import '../../services/music_permission_service.dart';
import '../../services/audio_content_service.dart';
import '../../services/youtube_audio_service.dart';
import '../../models/audio_item.dart';
import '../../models/youtube_song_model.dart';
import '../../providers/music_state_notifier.dart';
import '../../services/audio_handler.dart';
import '../../widgets/google_loading.dart';

/// Combined music library screen with Device Songs and YouTube tabs.
class MusicLibraryScreen extends StatefulWidget {
  const MusicLibraryScreen({super.key});

  @override
  State<MusicLibraryScreen> createState() => _MusicLibraryScreenState();
}

class _MusicLibraryScreenState extends State<MusicLibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  // Device songs
  final AudioContentService _deviceService = AudioContentService();
  final TextEditingController _deviceSearchCtrl = TextEditingController();
  List<AudioItem> _deviceSongs = [];
  List<AudioItem> _deviceFiltered = [];
  bool _deviceLoading = true;
  bool _usingDeviceSongs = false;

  // YouTube
  final YoutubeAudioService _ytService = YoutubeAudioService();
  final TextEditingController _ytSearchCtrl = TextEditingController();
  final FocusNode _ytSearchFocus = FocusNode();
  List<YoutubeSong> _ytResults = [];
  bool _ytLoading = false;
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging && mounted) setState(() {});
    });
    _initDeviceSongs();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _deviceSearchCtrl.dispose();
    _ytSearchCtrl.dispose();
    _ytSearchFocus.dispose();
    _ytService.dispose();
    super.dispose();
  }

  // ── Device Songs ────────────────────────────────────────────

  Future<void> _initDeviceSongs() async {
    setState(() => _deviceLoading = true);
    final granted = await MusicPermissionService.instance.requestStorage();
    if (granted) {
      await _loadDeviceSongs();
    } else {
      _loadSamples();
    }
    if (mounted) setState(() => _deviceLoading = false);
  }

  Future<void> _loadDeviceSongs() async {
    final songs = await _deviceService.getDeviceSongs();
    if (songs.isNotEmpty) {
      _deviceSongs = songs;
      _usingDeviceSongs = true;
    } else {
      _loadSamples();
    }
    _deviceFiltered = List.from(_deviceSongs);
  }

  void _loadSamples() {
    _deviceSongs = AudioContentService.sampleSongs;
    _usingDeviceSongs = false;
    _deviceFiltered = List.from(_deviceSongs);
  }

  void _filterDevice(String q) {
    setState(() {
      _deviceFiltered = q.isEmpty
          ? List.from(_deviceSongs)
          : _deviceSongs
              .where((s) =>
                  s.title.toLowerCase().contains(q) ||
                  s.artist.toLowerCase().contains(q))
              .toList();
    });
  }

  Future<void> _playDeviceSong(AudioItem song) async {
    final notifier = context.read<MusicStateNotifier>();
    final items = _deviceFiltered.map((s) => MediaItem(
      id: s.url,
      title: s.title,
      artist: s.artist,
      artUri: s.imageUrl != null ? Uri.tryParse(s.imageUrl!) : null,
      duration: s.duration,
    )).toList();

    final idx = _deviceFiltered.indexOf(song);
    final ok = await notifier.load(items, index: idx, autoPlay: true);

    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('error_loading_audio'))),
      );
    }

    if (_usingDeviceSongs && ok) {
      _prefetchArtwork(idx);
    }
  }

  void _prefetchArtwork(int idx) {
    final start = (idx - 3).clamp(0, _deviceFiltered.length - 1);
    final end = (idx + 3).clamp(0, _deviceFiltered.length - 1);
    for (var i = start; i <= end; i++) {
      _deviceService.getArtworkDataUri(
        int.tryParse(_deviceFiltered[i].id) ?? 0,
        ArtworkType.AUDIO,
      );
    }
  }

  // ── YouTube ─────────────────────────────────────────────────

  Future<void> _searchYoutube(String query) async {
    if (query.trim().isEmpty) return;
    setState(() => _ytLoading = true);
    final results = await _ytService.search(query.trim());
    if (mounted) {
      setState(() {
        _ytResults = results;
        _ytLoading = false;
        _hasSearched = true;
      });
    }
  }

  Future<void> _playYoutubeSong(YoutubeSong song, List<YoutubeSong> all, int index) async {
    final audioUrl = await _ytService.getAudioUrl(song.id);
    if (!mounted) return;
    if (audioUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('error_loading_audio'))),
      );
      return;
    }

    final notifier = context.read<MusicStateNotifier>();
    final ok = await notifier.load([
      MediaItem(
        id: audioUrl,
        title: song.title,
        artist: song.artist,
        artUri: Uri.tryParse(song.thumbnailUrl),
      ),
    ], index: 0, autoPlay: true);

    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('error_loading_audio'))),
      );
    }

    // Fetch remaining URLs in background
    for (var i = 0; i < all.length; i++) {
      if (i == index) continue;
      _ytService.getAudioUrl(all[i].id).then((url) {
        if (url == null || !mounted) return;
        try {
          musicHandler.addToQueue(MediaItem(
            id: url,
            title: all[i].title,
            artist: all[i].artist,
            artUri: Uri.tryParse(all[i].thumbnailUrl),
          ));
        } catch (_) {}
      });
    }
  }

  // ── Build ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('music_player')),
        backgroundColor: Colors.transparent,
        elevation: 0,
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: [
            Tab(text: context.tr('device_tab')),
            Tab(text: context.tr('online_tab')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildDeviceTab(cs),
          _buildYoutubeTab(cs),
        ],
      ),
    );
  }

  // ── Device Tab ──────────────────────────────────────────────

  Widget _buildDeviceTab(ColorScheme cs) {
    if (_deviceLoading) {
      return const Center(child: GoogleLoading(size: 48));
    }
    return Column(
      children: [
        if (!_usingDeviceSongs)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.tertiary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.tertiary.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: cs.tertiary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.tr('audio_permission_denied'),
                    style: TextStyle(color: cs.onSurface, fontSize: 13),
                  ),
                ),
                TextButton(
                  onPressed: _initDeviceSongs,
                  child: Text(context.tr('retry')),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _deviceSearchCtrl,
            onChanged: _filterDevice,
            decoration: InputDecoration(
              hintText: context.tr('search_songs'),
              prefixIcon: const Icon(Icons.search, size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: cs.onSurface.withValues(alpha: 0.06),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        Expanded(
          child: _deviceFiltered.isEmpty
              ? _emptyState(cs, Icons.music_note_rounded, context.tr('no_songs_found'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _deviceFiltered.length,
                  itemBuilder: (_, i) {
                    final song = _deviceFiltered[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      elevation: 0,
                      color: cs.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 48,
                            height: 48,
                            color: cs.primaryContainer,
                            child: const Icon(Icons.music_note_rounded),
                          ),
                        ),
                        title: Text(
                          song.title,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          song.artist,
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Icon(Icons.play_circle_fill_rounded, color: cs.primary, size: 28),
                        onTap: () => _playDeviceSong(song),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── YouTube Tab ─────────────────────────────────────────────

  Widget _buildYoutubeTab(ColorScheme cs) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _ytSearchCtrl,
            focusNode: _ytSearchFocus,
            onSubmitted: _searchYoutube,
            decoration: InputDecoration(
              hintText: context.tr('search_online_songs'),
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _ytSearchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 20),
                      onPressed: () {
                        _ytSearchCtrl.clear();
                        setState(() => _ytResults = []);
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: cs.onSurface.withValues(alpha: 0.06),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
            textInputAction: TextInputAction.search,
          ),
        ),
        Expanded(child: _buildYoutubeBody(cs)),
      ],
    );
  }

  Widget _buildYoutubeBody(ColorScheme cs) {
    if (_ytLoading) {
      return const Center(child: GoogleLoading(size: 48));
    }
    if (!_hasSearched) {
      return _emptyState(cs, Icons.cloud_outlined, context.tr('search_music_hint'));
    }
    if (_ytResults.isEmpty) {
      return _emptyState(cs, Icons.search_off_rounded, context.tr('no_results'));
    }
    return RefreshIndicator(
      onRefresh: () => _searchYoutube(_ytSearchCtrl.text),
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.8,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: _ytResults.length,
        itemBuilder: (_, i) => _buildYoutubeCard(_ytResults[i], i, cs),
      ),
    );
  }

  Widget _buildYoutubeCard(YoutubeSong song, int index, ColorScheme cs) {
    return GestureDetector(
      onTap: () => _playYoutubeSong(song, _ytResults, index),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: cs.surfaceContainerLow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    song.thumbnailUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      color: cs.surfaceContainerHighest,
                      child: Icon(Icons.music_note_rounded,
                          size: 40, color: cs.onSurface.withValues(alpha: 0.3)),
                    ),
                  ),
                  Positioned(
                    bottom: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        song.durationFormatted,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Icon(Icons.play_circle_fill_rounded,
                        color: Colors.white.withValues(alpha: 0.9), size: 28),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    song.artist,
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(ColorScheme cs, IconData icon, String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: cs.onSurface.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
