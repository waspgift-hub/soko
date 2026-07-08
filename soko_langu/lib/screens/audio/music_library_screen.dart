import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../extensions/context_tr.dart';
import '../../services/music_permission_service.dart';
import '../../services/audio_content_service.dart';
import '../../services/youtube_audio_service.dart';
import '../../models/audio_item.dart';
import '../../models/youtube_song_model.dart';
import '../../providers/music_state_notifier.dart';
import '../../services/audio_handler.dart';
import '../../app/routes.dart';
import '../../widgets/google_loading.dart';
import '../../theme/app_animations.dart';

enum _LibraryTab { songs, albums, artists, genres, youtube }

class MusicLibraryScreen extends StatefulWidget {
  const MusicLibraryScreen({super.key});
  @override
  State<MusicLibraryScreen> createState() => _MusicLibraryScreenState();
}

class _MusicLibraryScreenState extends State<MusicLibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  final AudioContentService _deviceService = AudioContentService();
  final YoutubeAudioService _ytService = YoutubeAudioService();
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  List<AudioItem> _deviceSongs = [];
  List<AudioItem> _deviceFiltered = [];
  List<AudioItem> _selectedSongs = [];
  bool _deviceLoading = true;
  bool _usingDeviceSongs = false;
  bool _multiSelectMode = false;
  bool _showSearch = false;
  bool _showFavoritesOnly = false;
  final Set<String> _favoriteIds = {};

  // Albums / Artists / Genres
  List<AlbumModel> _albums = [];
  List<ArtistModel> _artists = [];
  List<GenreModel> _genres = [];
  bool _albumsLoading = false;
  bool _artistsLoading = false;
  bool _genresLoading = false;

  // YouTube
  List<YoutubeSong> _ytResults = [];
  bool _ytLoading = false;
  bool _hasSearched = false;
  final TextEditingController _ytSearchCtrl = TextEditingController();

  // Sort
  String _sortBy = 'title';
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _LibraryTab.values.length, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) setState(() {});
    });
    _initDeviceSongs();
    _loadAlbums();
    _loadArtists();
    _loadGenres();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    _ytSearchCtrl.dispose();
    _searchFocus.dispose();
    _ytService.dispose();
    super.dispose();
  }

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
    _applySort();
  }

  void _loadSamples() {
    _deviceSongs = AudioContentService.sampleSongs;
    _usingDeviceSongs = false;
    _applySort();
  }

  Future<void> _loadAlbums() async {
    setState(() => _albumsLoading = true);
    final albums = await _deviceService.getAlbums();
    if (mounted) setState(() { _albums = albums; _albumsLoading = false; });
  }

  Future<void> _loadArtists() async {
    setState(() => _artistsLoading = true);
    final artists = await _deviceService.getArtists();
    if (mounted) setState(() { _artists = artists; _artistsLoading = false; });
  }

  Future<void> _loadGenres() async {
    setState(() => _genresLoading = true);
    final genres = await _deviceService.getGenres();
    if (mounted) setState(() { _genres = genres; _genresLoading = false; });
  }

  void _applySort() {
    var sorted = List<AudioItem>.from(_deviceSongs);
    switch (_sortBy) {
      case 'title':
        sorted.sort((a, b) => a.title.compareTo(b.title));
      case 'artist':
        sorted.sort((a, b) => a.artist.compareTo(b.artist));
      case 'duration':
        sorted.sort((a, b) => a.duration.compareTo(b.duration));
    }
    if (!_sortAscending) sorted = sorted.reversed.toList();
    _deviceFiltered = sorted;
  }

  void _filterDevice(String q) {
    setState(() {
      _deviceFiltered = q.isEmpty
          ? List.from(_deviceSongs)
          : _deviceSongs.where((s) =>
              s.title.toLowerCase().contains(q.toLowerCase()) ||
              s.artist.toLowerCase().contains(q.toLowerCase())).toList();
    });
  }

  void _toggleSort(String field) {
    if (_sortBy == field) {
      _sortAscending = !_sortAscending;
    } else {
      _sortBy = field;
      _sortAscending = true;
    }
    _applySort();
    setState(() {});
  }

  void _toggleMultiSelect() {
    setState(() {
      _multiSelectMode = !_multiSelectMode;
      if (!_multiSelectMode) _selectedSongs.clear();
    });
    HapticFeedback.mediumImpact();
  }

  void _toggleFavorite(String songId) {
    setState(() {
      if (_favoriteIds.contains(songId)) {
        _favoriteIds.remove(songId);
      } else {
        _favoriteIds.add(songId);
      }
    });
    HapticFeedback.lightImpact();
  }

  Future<void> _playDeviceSong(AudioItem song) async {
    try {
      final notifier = context.read<MusicStateNotifier>();
      final items = _deviceFiltered.map((s) => MediaItem(
        id: s.url,
        title: s.title,
        artist: s.artist,
        artUri: s.imageUrl != null ? Uri.tryParse(s.imageUrl!) : null,
        duration: s.duration,
        extras: s.youtubeVideoId != null
            ? {'youtubeVideoId': s.youtubeVideoId}
            : null,
      )).toList();
      final idx = _deviceFiltered.indexOf(song);
      final ok = await notifier.load(items, index: idx, autoPlay: true);
      if (!ok && mounted) {
        _showError(notifier.lastError.isNotEmpty
            ? notifier.lastError : context.tr('error_loading_audio'));
        return;
      }
      if (mounted && GoRouterState.of(context).uri.toString() != AppRoutes.audioPlayer) {
        context.push(AppRoutes.audioPlayer);
      }
    } on SocketException catch (_) {
      if (mounted) _showError(context.tr('no_network'));
    } on TimeoutException catch (_) {
      if (mounted) _showError(context.tr('no_network'));
    } on PlayerException catch (e) {
      if (mounted) _showError('${context.tr('playback_error')}: ${e.message}');
    } catch (e, stack) {
      debugPrint('[LIBRARY] ❌ $e\n$stack');
      if (mounted) _showError(context.tr('error_loading_audio'));
    }
  }

  Future<void> _playYoutubeSong(YoutubeSong song, List<YoutubeSong> all, int index) async {
    try {
      String? audioUrl;
      String? videoUrl;
      try {
        final results = await Future.wait([
          _ytService.getAudioUrl(song.id),
          _ytService.getBestMuxedStream(song.id),
        ]);
        audioUrl = results[0];
        videoUrl = results[1];
      } on SocketException catch (_) {
        if (mounted) { _showError(context.tr('no_network')); return; }
      } on TimeoutException catch (_) {
        if (mounted) { _showError(context.tr('no_network')); return; }
      } catch (e) { debugPrint('[LIBRARY] yt url error: $e'); }
      if (!mounted) return;
      if (audioUrl == null || audioUrl.isEmpty) {
        _showError(context.tr('no_network')); return;
      }
      final notifier = context.read<MusicStateNotifier>();
      final ok = await notifier.load([
        MediaItem(id: audioUrl, title: song.title, artist: song.artist,
            artUri: Uri.tryParse(song.thumbnailUrl),
            extras: {'videoUrl': videoUrl, 'youtubeVideoId': song.id}),
      ], index: 0, autoPlay: true);
      if (!ok && mounted) { _showError(context.tr('error_loading_audio')); return; }
      if (mounted && GoRouterState.of(context).uri.toString() != AppRoutes.audioPlayer) {
        context.push(AppRoutes.audioPlayer);
      }
      for (var i = 0; i < all.length; i++) {
        if (i == index) continue;
        final idx = i;
        _ytService.getAudioUrl(all[idx].id).then((url) {
          _ytService.getBestMuxedStream(all[idx].id).then((muxed) {
            if (url == null || !mounted) return;
            final ytId = all[idx].id;
            musicHandler.addToQueue(MediaItem(id: url,
                title: all[idx].title, artist: all[idx].artist,
                artUri: Uri.tryParse(all[idx].thumbnailUrl),
                extras: {'youtubeVideoId': ytId, if (muxed != null) 'videoUrl': muxed}));
          });
        });
      }
    } on PlayerException catch (e) {
      if (mounted) _showError('${context.tr('playback_error')}: ${e.message}');
    } on SocketException catch (_) {
      if (mounted) _showError(context.tr('no_network'));
    } on TimeoutException catch (_) {
      if (mounted) _showError(context.tr('no_network'));
    } catch (e, stack) {
      debugPrint('[LIBRARY] ❌ yt play error: $e\n$stack');
      if (mounted) _showError(context.tr('error_loading_audio'));
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _searchYoutube(String query) async {
    if (query.trim().isEmpty) return;
    setState(() => _ytLoading = true);
    try {
      final results = await _ytService.search(query.trim());
      if (mounted) setState(() { _ytResults = results; _ytLoading = false; _hasSearched = true; });
    } catch (e) {
      debugPrint('Youtube search error: $e');
      if (mounted) { setState(() => _ytLoading = false); _showError(context.tr('no_network')); }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_multiSelectMode
            ? '${_selectedSongs.length} selected'
            : context.tr('music_player')),
        actions: [
          if (!_multiSelectMode) ...[
            IconButton(
              icon: Icon(_showFavoritesOnly ? Icons.favorite_rounded : Icons.favorite_outline_rounded,
                  color: _showFavoritesOnly ? Colors.pink : null),
              onPressed: () => setState(() => _showFavoritesOnly = !_showFavoritesOnly),
              tooltip: 'Favorites',
            ),
            IconButton(
              icon: Icon(_showSearch ? Icons.search_off_rounded : Icons.search_rounded),
              onPressed: () => setState(() => _showSearch = !_showSearch),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.sort_rounded),
              onSelected: _toggleSort,
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'title',
                  child: Row(children: [
                    Text('Title'),
                    if (_sortBy == 'title')
                      Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 16),
                  ]),
                ),
                PopupMenuItem(
                  value: 'artist',
                  child: Row(children: [
                    Text('Artist'),
                    if (_sortBy == 'artist')
                      Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 16),
                  ]),
                ),
                PopupMenuItem(
                  value: 'duration',
                  child: Row(children: [
                    Text('Duration'),
                    if (_sortBy == 'duration')
                      Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 16),
                  ]),
                ),
              ],
            ),
          ] else ...[
            TextButton.icon(
              onPressed: () {
                if (_selectedSongs.isEmpty) return;
                final items = _selectedSongs.map((s) => MediaItem(
                  id: s.url, title: s.title, artist: s.artist,
                  artUri: s.imageUrl != null ? Uri.tryParse(s.imageUrl!) : null,
                  duration: s.duration,
                )).toList();
                context.read<MusicStateNotifier>().load(items, autoPlay: true);
                if (mounted && GoRouterState.of(context).uri.toString() != AppRoutes.audioPlayer) {
                  context.push(AppRoutes.audioPlayer);
                }
              },
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Play'),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: _toggleMultiSelect,
            ),
          ],
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          tabs: [
            Tab(text: 'Songs'),
            Tab(text: 'Albums'),
            Tab(text: 'Artists'),
            Tab(text: 'Genres'),
            Tab(text: 'YouTube'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_showSearch && _tabCtrl.index == 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: TextField(
                controller: _searchCtrl,
                focusNode: _searchFocus,
                onChanged: _filterDevice,
                decoration: InputDecoration(
                  hintText: 'Search songs...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.clear_rounded, size: 20),
                          onPressed: () { _searchCtrl.clear(); _filterDevice(''); })
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              physics: const BouncingScrollPhysics(),
              children: [
                _buildSongsTab(cs),
                _buildAlbumsTab(cs),
                _buildArtistsTab(cs),
                _buildGenresTab(cs),
                _buildYoutubeTab(cs),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Songs Tab ──

  Widget _buildSongsTab(ColorScheme cs) {
    if (_deviceLoading) return const Center(child: GoogleLoading(size: 48));
    if (!_usingDeviceSongs) {
      return Column(children: [
        _permissionBanner(cs),
        Expanded(child: _buildSongList(cs)),
      ]);
    }
    return _buildSongList(cs);
  }

  Widget _permissionBanner(ColorScheme cs) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.tertiary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.tertiary.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(Icons.info_outline, color: cs.tertiary, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(context.tr('audio_permission_denied'),
            style: TextStyle(color: cs.onSurface, fontSize: 13))),
        TextButton(onPressed: _initDeviceSongs, child: Text(context.tr('retry'))),
      ]),
    );
  }

  Widget _buildSongList(ColorScheme cs) {
    var songs = _deviceFiltered;
    if (_showFavoritesOnly) {
      songs = songs.where((s) => _favoriteIds.contains(s.id)).toList();
    }
    if (songs.isEmpty) {
      return _emptyState(cs, Icons.music_note_rounded,
          _showFavoritesOnly ? 'No favorite songs' : 'No songs');
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      physics: const BouncingScrollPhysics(),
      itemCount: songs.length,
      itemBuilder: (_, i) {
        final song = songs[i];
        final isSelected = _selectedSongs.contains(song);
        final isFavorite = _favoriteIds.contains(song.id);

        return AnimatedScaleIn(
          delay: Duration(milliseconds: 20 * i),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Material(
              color: isSelected
                  ? cs.primary.withValues(alpha: 0.12)
                  : i.isEven
                      ? cs.surfaceContainerLow.withValues(alpha: 0.5)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  if (_multiSelectMode) {
                    setState(() {
                      if (isSelected) {
                        _selectedSongs.remove(song);
                      } else {
                        _selectedSongs.add(song);
                      }
                    });
                  } else {
                    _playDeviceSong(song);
                  }
                },
                onLongPress: () {
                  if (!_multiSelectMode) {
                    _toggleMultiSelect();
                    setState(() => _selectedSongs.add(song));
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(children: [
                    if (_multiSelectMode)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(
                          isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                          color: isSelected ? cs.primary : cs.onSurface.withValues(alpha: 0.3),
                          size: 22,
                        ),
                      ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 50,
                        height: 50,
                        color: cs.primaryContainer,
                        child: song.imageUrl != null
                            ? Image.network(song.imageUrl!, fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    Icon(Icons.music_note_rounded, color: cs.onPrimaryContainer))
                            : Icon(Icons.music_note_rounded, color: cs.onPrimaryContainer),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(song.title,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          Row(
                            children: [
                              Text(song.artist,
                                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              if (isFavorite) ...[
                                const SizedBox(width: 6),
                                Icon(Icons.favorite_rounded, size: 12, color: Colors.pink),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _toggleFavorite(song.id),
                      child: Icon(
                        isFavorite ? Icons.favorite_rounded : Icons.favorite_outline_rounded,
                        color: isFavorite ? Colors.pink : cs.onSurface.withValues(alpha: 0.3),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.play_circle_fill_rounded, color: cs.primary, size: 28),
                  ]),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Albums Tab ──

  Widget _buildAlbumsTab(ColorScheme cs) {
    if (_albumsLoading) return const Center(child: GoogleLoading(size: 48));
    if (_albums.isEmpty) return _emptyState(cs, Icons.album_rounded, 'No albums');
    return RefreshIndicator(
      onRefresh: _loadAlbums,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        physics: const BouncingScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, childAspectRatio: 0.9, crossAxisSpacing: 12, mainAxisSpacing: 12,
        ),
        itemCount: _albums.length,
        itemBuilder: (_, i) => _albumCard(_albums[i], cs, i),
      ),
    );
  }

  Widget _albumCard(AlbumModel album, ColorScheme cs, int index) {
    return AnimatedScaleIn(
      delay: Duration(milliseconds: 50 * index),
      child: GestureDetector(
        onTap: () async {
          final songs = await _deviceService.getAlbumSongs(album.id);
          if (!mounted) return;
          _showSongList(cs, album.album, ArtworkType.ALBUM, album.id,
              songs.map((s) => _deviceService.songToItem(s)).toList());
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: cs.surfaceContainerLow,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Container(
                width: double.infinity,
                color: cs.surfaceContainerHighest,
                child: AlbumArtImage(albumId: album.id, type: ArtworkType.ALBUM),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(album.album, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                Text('${album.numOfSongs} songs',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Artists Tab ──

  Widget _buildArtistsTab(ColorScheme cs) {
    if (_artistsLoading) return const Center(child: GoogleLoading(size: 48));
    if (_artists.isEmpty) return _emptyState(cs, Icons.person_rounded, 'No artists');
    return RefreshIndicator(
      onRefresh: _loadArtists,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        physics: const BouncingScrollPhysics(),
        itemCount: _artists.length,
        itemBuilder: (_, i) {
          final artist = _artists[i];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: cs.primaryContainer,
              child: Text(artist.artist.isNotEmpty ? artist.artist[0].toUpperCase() : '?',
                  style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.bold)),
            ),
            title: Text(artist.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${artist.numberOfAlbums} albums · ${artist.numberOfTracks} songs',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            onTap: () async {
              final songs = await _deviceService.getArtistSongs(artist.id);
              if (!mounted) return;
              _showSongList(cs, artist.artist, ArtworkType.ARTIST, artist.id,
                  songs.map((s) => _deviceService.songToItem(s)).toList());
            },
          );
        },
      ),
    );
  }

  // ── Genres Tab ──

  Widget _buildGenresTab(ColorScheme cs) {
    if (_genresLoading) return const Center(child: GoogleLoading(size: 48));
    if (_genres.isEmpty) return _emptyState(cs, Icons.category_rounded, 'No genres');
    return RefreshIndicator(
      onRefresh: _loadGenres,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        physics: const BouncingScrollPhysics(),
        itemCount: _genres.length,
        itemBuilder: (_, i) {
          final genre = _genres[i];
          return ListTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.music_note_rounded, color: cs.onPrimaryContainer, size: 22),
            ),
            title: Text(genre.genre, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${genre.numOfSongs} songs',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            onTap: () async {
              final songs = await _deviceService.getGenreSongs(genre.id);
              if (!mounted) return;
              _showSongList(cs, genre.genre, ArtworkType.GENRE, genre.id,
                  songs.map((s) => _deviceService.songToItem(s)).toList());
            },
          );
        },
      ),
    );
  }

  // ── Song list bottom sheet ──

  void _showSongList(ColorScheme cs, String title, ArtworkType artType, int artId,
      List<AudioItem> songs) {
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollCtrl) => Column(children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: cs.onSurface.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Row(children: [
              Expanded(child: Text(title,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: cs.onSurface))),
              TextButton(onPressed: () => _playDeviceSong(songs.first),
                  child: Text('Play All')),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: scrollCtrl,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              physics: const BouncingScrollPhysics(),
              itemCount: songs.length,
              itemBuilder: (_, i) {
                final s = songs[i];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  leading: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.music_note_rounded, size: 20, color: cs.onPrimaryContainer),
                  ),
                  title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14)),
                  subtitle: Text(s.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  trailing: Icon(Icons.play_circle_fill_rounded, color: cs.primary, size: 22),
                  onTap: () { Navigator.pop(ctx); _playDeviceSong(s); },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  // ── YouTube Tab ──

  Widget _buildYoutubeTab(ColorScheme cs) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: TextField(
          controller: _ytSearchCtrl,
          onSubmitted: _searchYoutube,
          decoration: InputDecoration(
            hintText: 'Search YouTube...',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: _ytSearchCtrl.text.isNotEmpty
                ? IconButton(icon: const Icon(Icons.clear_rounded, size: 20),
                    onPressed: () { _ytSearchCtrl.clear(); setState(() => _ytResults = []); })
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.3),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
          textInputAction: TextInputAction.search,
        ),
      ),
      Expanded(child: _buildYoutubeBody(cs)),
    ]);
  }

  Widget _buildYoutubeBody(ColorScheme cs) {
    if (_ytLoading) return const Center(child: GoogleLoading(size: 48));
    if (!_hasSearched) return _emptyState(cs, Icons.cloud_outlined, 'Search for online songs');
    if (_ytResults.isEmpty) return _emptyState(cs, Icons.search_off_rounded, 'No results');
    return RefreshIndicator(
      onRefresh: () => _searchYoutube(_ytSearchCtrl.text),
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        physics: const BouncingScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, childAspectRatio: 0.85, crossAxisSpacing: 10, mainAxisSpacing: 10,
        ),
        itemCount: _ytResults.length,
        itemBuilder: (_, i) => _ytCard(_ytResults[i], i, cs),
      ),
    );
  }

  Widget _ytCard(YoutubeSong song, int index, ColorScheme cs) {
    return AnimatedScaleIn(
      delay: Duration(milliseconds: 50 * index),
      child: GestureDetector(
        onTap: () => _playYoutubeSong(song, _ytResults, index),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: cs.surfaceContainerLow,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Stack(fit: StackFit.expand, children: [
                Image.network(song.thumbnailUrl, fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(color: cs.surfaceContainerHighest,
                      child: Icon(Icons.music_note_rounded, size: 40,
                          color: cs.onSurface.withValues(alpha: 0.3)))),
                Positioned(bottom: 6, right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(song.durationFormatted,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                ),
                Positioned(right: 8, top: 8,
                  child: Icon(Icons.play_circle_fill_rounded,
                      color: Colors.white.withValues(alpha: 0.9), size: 28)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _emptyState(ColorScheme cs, IconData icon, String message) {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 72, height: 72,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 32, color: cs.onSurface.withValues(alpha: 0.2)),
      ),
      const SizedBox(height: 16),
      Text(message, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
          textAlign: TextAlign.center),
    ]));
  }
}

// ── Album art helper widget ──

class AlbumArtImage extends StatelessWidget {
  final int albumId;
  final ArtworkType type;
  const AlbumArtImage({super.key, required this.albumId, required this.type});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: AudioContentService().getArtwork(albumId, type),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: SizedBox(width: 24, height: 24,
              child: CircularProgressIndicator(strokeWidth: 2)));
        }
        if (snap.data != null) {
          return Image.memory(snap.data!, fit: BoxFit.cover);
        }
        return Center(child: Icon(Icons.album_rounded, size: 40,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2)));
      },
    );
  }
}
