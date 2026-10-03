import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../extensions/context_tr.dart';
import '../../services/music_library_service.dart';
import '../../services/profile_media_controller.dart';
import '../../services/profile_media_session.dart';
import '../../services/youtube_search_service.dart';
import '../../widgets/ads/ad_slot.dart';
import '../../widgets/song_cover.dart';
import '../../theme/app_dimens.dart';
import '../../services/ads/ad_config.dart';

/// Music hub: songs stored on the user's own phone plus YouTube search.
/// Local playback is fully offline; YouTube search goes through the
/// server-side proxy (key never ships in the app) and playback uses the
/// official nocookie embed ? no downloading, no ToS breach.
class MusicScreen extends StatelessWidget {
  const MusicScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr('music')),
          bottom: TabBar(
            tabs: [
              Tab(text: context.tr('my_songs'), icon: const Icon(Icons.smartphone)),
              const Tab(text: 'YouTube', icon: Icon(Icons.ondemand_video)),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_LocalSongsTab(), _YouTubeTab()],
        ),
      ),
    );
  }
}

String _fmtMs(int ms) {
  final d = Duration(milliseconds: ms);
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
}

  ProfileMediaItem _songItem(LocalSong s) => ProfileMediaItem(
        id: 'local:${s.id}',
        title: s.artist.isEmpty || s.artist == 'Unknown'
            ? s.title
            : '${s.title} - ${s.artist}',
        videoUrl: '',
        localPath: s.path,
        // Feed the media notification real metadata so the lock screen shows
        // artist/album instead of the combined display title.
        artist: s.artist == 'Unknown' ? '' : s.artist,
        album: s.album == 'Unknown' ? '' : s.album,
        duration:
            s.durationMs > 0 ? Duration(milliseconds: s.durationMs) : null,
        // Carried on the item so the player screen shows the real cover
        // without asking for the media permission a second time.
        artwork: s.artwork,
      );

class _LocalSongsTab extends StatefulWidget {
  const _LocalSongsTab();

  @override
  State<_LocalSongsTab> createState() => _LocalSongsTabState();
}

class _LocalSongsTabState extends State<_LocalSongsTab>
    with AutomaticKeepAliveClientMixin {
  final MusicLibraryService _library = MusicLibraryService();
  List<LocalSong>? _songs;
  bool _loading = true;
  bool _denied = false;

  /// On-device library search. Held in state so typing filters the list that is
  /// already in memory — the songs are already scanned, so this never touches
  /// the network or re-reads the media store.
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  bool get _supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_supported) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    var granted = await _library.hasPermission();
    if (!granted) {
      if (mounted) {
        setState(() {
          _loading = false;
          _denied = true;
        });
      }
      return;
    }
    final songs = await _library.loadSongs();
    if (mounted) {
      setState(() {
        _songs = songs;
        _loading = false;
        _denied = false;
      });
    }
  }

  Future<void> _request() async {
    setState(() => _loading = true);
    final granted = await _library.requestPermission();
    if (!granted) {
      if (mounted) {
        setState(() {
          _loading = false;
          _denied = true;
        });
      }
      return;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!_supported) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            context.tr('music_not_supported'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_denied) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.music_off, size: 56),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _request,
              icon: const Icon(Icons.library_music),
              label: Text(context.tr('allow_music_access')),
            ),
          ],
        ),
      );
    }
    final all = _songs ?? const <LocalSong>[];
    // Search filters what is shown but the play queue stays the whole library,
    // so tapping a result does not stop the next song after it.
    final songs = MusicLibraryService.search(all, _query);
    if (all.isEmpty) {
      return Center(child: Text(context.tr('no_songs_found')));
    }
    if (songs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 48),
            const SizedBox(height: 8),
            Text('${context.tr('no_songs_found')} — "$_query"'),
          ],
        ),
      );
    }
    return Column(
      children: [
        _buildSearchField(),
        Expanded(
          child: ListView.separated(
            itemCount: songs.length + 1,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              if (i == songs.length) {
                // Footer placement: after the last track so the ad is never
                // between two tappable rows and never interferes with playback
                // controls.
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppInsets.lg),
                  child: AdSlot(
                    placement: AdPlacement.musicFeedFooter,
                    variant: AdSlotVariant.feedGap,
                  ),
                );
              }
              final s = songs[i];
              return ListTile(
                leading: SongCover(song: s, size: 48),
                title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  s.displayArtist.isEmpty ? s.displayAlbum : s.displayArtist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(
                  _fmtMs(s.durationMs),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                onTap: () async {
                  await ProfileMediaSession.instance.playMusicQueue(
                    items: all.map(_songItem).toList(),
                    startAt: all.indexOf(s),
                  );
                  if (context.mounted) context.push(AppRoutes.nowPlaying);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppInsets.lg, AppInsets.sm, AppInsets.lg, 4),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search),
          hintText: context.tr('search_local_songs', 'Search songs on your phone'),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _query = '');
                  },
                ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;
}

class _YouTubeTab extends StatefulWidget {
  const _YouTubeTab();

  @override
  State<_YouTubeTab> createState() => _YouTubeTabState();
}

class _YouTubeTabState extends State<_YouTubeTab>
    with AutomaticKeepAliveClientMixin {
  final YouTubeSearchService _search = YouTubeSearchService();
  final TextEditingController _query = TextEditingController();
  List<YouTubeVideo>? _results;
  bool _loading = false;
  bool _notConfigured = false;
  bool _searched = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final q = _query.text.trim();
    if (q.length < 2) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _notConfigured = false;
    });
    try {
      final results = await _search.search(q);
      if (mounted) {
        setState(() {
          _results = results;
          _loading = false;
          _searched = true;
        });
      }
    } on StateError catch (e) {
      if (e.message == 'YOUTUBE_NOT_CONFIGURED' && mounted) {
        setState(() {
          _loading = false;
          _notConfigured = true;
          _searched = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _query,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _run(),
                  decoration: InputDecoration(
                    hintText: context.tr('search_youtube'),
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _run, child: Text(context.tr('search'))),
            ],
          ),
        ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_notConfigured) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            context.tr('youtube_not_configured'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final results = _results;
    if (results == null) {
      return Center(
        child: Text(
          context.tr('search_youtube'),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    if (results.isEmpty && _searched) {
      return Center(child: Text(context.tr('no_songs_found')));
    }
    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final v = results[i];
        return ListTile(
          leading: v.thumbnail.isEmpty
              ? const CircleAvatar(child: Icon(Icons.ondemand_video))
              : ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    v.thumbnail,
                    width: 96,
                    height: 54,
                    fit: BoxFit.cover,
                  ),
                ),
          title: Text(v.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            v.channel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () async {
            await ProfileMediaSession.instance.playMusicQueue(
              items: [
                ProfileMediaItem(
                  id: 'yt:${v.videoId}',
                  title: v.title,
                  videoUrl: v.watchUrl,
                  thumbnailUrl: v.thumbnail.isEmpty ? null : v.thumbnail,
                ),
              ],
            );
            if (context.mounted) context.push(AppRoutes.nowPlaying);
          },
        );
      },
    );
  }

  @override
  bool get wantKeepAlive => true;
}
