import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:on_audio_query/on_audio_query.dart';

/// On-device music library. Audio stays on the user's device; no upload occurs.
class LocalMusicScreen extends StatefulWidget {
  const LocalMusicScreen({super.key});

  @override
  State<LocalMusicScreen> createState() => _LocalMusicScreenState();
}

class _LocalMusicScreenState extends State<LocalMusicScreen> {
  final OnAudioQuery _query = OnAudioQuery();
  final AudioPlayer _player = AudioPlayer();
  List<SongModel> _songs = [];
  bool _loading = true;
  bool _permissionDenied = false;
  String? _error;
  int? _playingId;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player.playerStateStream.listen((state) {
      if (mounted) setState(() => _playing = state.playing);
    });
    _loadSongs();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _loadSongs() async {
    setState(() {
      _loading = true;
      _error = null;
      _permissionDenied = false;
    });
    try {
      final granted = await _query.checkAndRequest(retryRequest: true);
      if (!granted) {
        if (mounted) setState(() => _permissionDenied = true);
        return;
      }
      final songs = await _query.querySongs(
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );
      if (mounted) setState(() => _songs = songs);
    } catch (e) {
      if (mounted) setState(() => _error = 'Imeshindikana kusoma nyimbo za simu. Tafadhali jaribu tena.');
      debugPrint('LocalMusicScreen: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _play(SongModel song) async {
    final uri = song.uri;
    if (uri == null || uri.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Faili hii haiwezi kuchezwa.')),
      );
      return;
    }
    try {
      if (_playingId == song.id && _playing) {
        await _player.pause();
      } else if (_playingId == song.id) {
        await _player.play();
      } else {
        await _player.setAudioSource(
          AudioSource.uri(
            Uri.parse(uri),
            tag: MediaItem(
              id: uri,
              title: song.title.isEmpty ? 'Wimbo usio na jina' : song.title,
              artist: (song.artist == null || song.artist!.trim().isEmpty || song.artist == '<unknown>') ? 'Msanii hajatajwa' : song.artist!,
              album: (song.album == null || song.album!.trim().isEmpty || song.album == '<unknown>') ? 'Nyimbo kwenye simu' : song.album!,
            ),
          ),
        );
        if (!mounted) return;
        setState(() => _playingId = song.id);
        await _player.play();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Playback imeshindikana kwa faili hili.')),
        );
      }
      debugPrint('Local music playback error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nyimbo kwenye simu'),
        actions: [
          IconButton(
            tooltip: 'Changanua tena',
            onPressed: _loading ? null : _loadSongs,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _permissionDenied
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.folder_off_outlined, size: 56),
                        const SizedBox(height: 12),
                        const Text('Ruhusu SokoVibe Music kuona faili za sauti ili kuonyesha nyimbo zilizohifadhiwa kwenye simu yako.', textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _loadSongs,
                          icon: const Icon(Icons.lock_open),
                          label: const Text('Omba ruhusa tena'),
                        ),
                      ],
                    ),
                  ),
                )
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(onPressed: _loadSongs, child: const Text('Jaribu tena')),
                        ],
                      ),
                    )
                  : _songs.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.library_music_outlined, size: 58, color: colors.primary),
                                const SizedBox(height: 12),
                                const Text('Hakuna nyimbo zilizopatikana kwenye simu.', textAlign: TextAlign.center),
                                const SizedBox(height: 8),
                                const Text('Hakikisha faili za MP3 au audio zipo kwenye kifaa, kisha changanua tena.', textAlign: TextAlign.center),
                                const SizedBox(height: 12),
                                FilledButton.icon(onPressed: _loadSongs, icon: const Icon(Icons.refresh), label: const Text('Changanua tena')),
                              ],
                            ),
                          ),
                        )
                      : Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text('${_songs.length} nyimbo kwenye kifaa', style: Theme.of(context).textTheme.titleMedium),
                              ),
                            ),
                            Expanded(
                              child: ListView.separated(
                                itemCount: _songs.length,
                                separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                                itemBuilder: (context, index) {
                                  final song = _songs[index];
                                  final current = _playingId == song.id;
                                  return ListTile(
                                    leading: QueryArtworkWidget(
                                      id: song.id,
                                      type: ArtworkType.AUDIO,
                                      nullArtworkWidget: CircleAvatar(
                                        backgroundColor: colors.primaryContainer,
                                        child: Icon(Icons.music_note, color: colors.onPrimaryContainer),
                                      ),
                                    ),
                                    title: Text(song.title.isEmpty ? 'Wimbo usio na jina' : song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    subtitle: Text(
                                      [song.artist, song.album].where((s) => s != null && s.trim().isNotEmpty && s != '<unknown>').join(' • ').ifEmpty('Msanii hajatajwa'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: IconButton.filledTonal(
                                      tooltip: current && _playing ? 'Sitisha' : 'Cheza',
                                      onPressed: () => _play(song),
                                      icon: Icon(current && _playing ? Icons.pause : Icons.play_arrow),
                                    ),
                                    onTap: () => _play(song),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
