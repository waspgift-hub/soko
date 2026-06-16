import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../models/audio_item.dart';
import '../../services/audio_content_service.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';
import '../../widgets/google_loading.dart';

class AudioListScreen extends StatefulWidget {
  const AudioListScreen({super.key});

  @override
  State<AudioListScreen> createState() => _AudioListScreenState();
}

class _AudioListScreenState extends State<AudioListScreen> {
  final AudioContentService _service = AudioContentService();
  final _searchCtrl = TextEditingController();
  List<AudioItem> _songs = [];
  List<AudioItem> _filtered = [];
  bool _loading = true;
  bool _usingDeviceSongs = false;

  @override
  void initState() {
    super.initState();
    _initAudio();
  }

  Future<void> _initAudio() async {
    setState(() => _loading = true);
    final status = await Permission.audio.status;
    if (status.isGranted) {
      await _loadDeviceSongs();
    } else if (status.isDenied) {
      final granted = await Permission.audio.request();
      if (granted.isGranted) {
        await _loadDeviceSongs();
      } else {
        _loadSamples();
      }
    } else {
      _loadSamples();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadDeviceSongs() async {
    final songs = await _service.getDeviceSongs();
    if (songs.isNotEmpty) {
      _songs = songs;
      _usingDeviceSongs = true;
    } else {
      _loadSamples();
    }
    _filtered = List.from(_songs);
  }

  void _loadSamples() {
    _songs = AudioContentService.sampleSongs;
    _usingDeviceSongs = false;
    _filtered = List.from(_songs);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _search(String q) {
    setState(() {
      _filtered = q.isEmpty
          ? List.from(_songs)
          : _songs
              .where((s) =>
                  s.title.toLowerCase().contains(q) ||
                  s.artist.toLowerCase().contains(q))
              .toList();
    });
  }

  Future<void> _playSong(AudioItem song) async {
    final urls = _filtered.map((s) => s.url).toList();
    final titles = _filtered.map((s) => s.title).toList();
    final artists = _filtered.map((s) => s.artist).toList();
    final idx = _filtered.indexOf(song);

    // Build image URLs — use existing imageUrl or try fetching artwork for device songs
    final images = List<String>.generate(_filtered.length, (i) {
      final s = _filtered[i];
      return s.imageUrl ?? '';
    });
    if (_usingDeviceSongs && images[idx].isEmpty) {
      final dataUri = await _service.getArtworkDataUri(
        int.tryParse(song.id) ?? 0,
        ArtworkType.AUDIO,
      );
      if (dataUri != null) images[idx] = dataUri;
    }

    if (!mounted) return;
    context.push(AppRoutes.audioPlayer, extra: {
      'urls': urls,
      'titles': titles,
      'artists': artists,
      'imageUrls': images,
      'initialIndex': idx,
      'title': song.title,
      'artist': song.artist,
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('all_songs')),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: GoogleLoading(size: 48))
          : Column(
              children: [
                if (!_usingDeviceSongs)
                  Container(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.tertiary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: cs.tertiary.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: cs.tertiary, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            context.tr('audio_permission_denied'),
                            style:
                                TextStyle(color: cs.onSurface, fontSize: 13),
                          ),
                        ),
                        TextButton(
                          onPressed: _initAudio,
                          child: Text(context.tr('now')),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: _search,
                    decoration: InputDecoration(
                      hintText: context.tr('search_songs'),
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: cs.onSurface.withValues(alpha: 0.06),
                    ),
                  ),
                ),
                Expanded(
                  child: _filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.music_note,
                                  size: 64,
                                  color: cs.onSurface.withValues(alpha: 0.3)),
                              const SizedBox(height: 16),
                          Text(
                            context.tr('audio_permission_denied'),
                            style:
                                TextStyle(color: cs.onSurface, fontSize: 13),
                          ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) {
                            final song = _filtered[i];
                            return Card(
                              margin:
                                  const EdgeInsets.symmetric(vertical: 4),
                              child: ListTile(
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: _usingDeviceSongs
                                      ? QueryArtworkWidget(
                                          id: int.tryParse(song.id) ?? 0,
                                          type: ArtworkType.AUDIO,
                                          size: 200,
                                          quality: 100,
                                          artworkFit: BoxFit.cover,
                                          artworkBorder: BorderRadius.zero,
                                          artworkWidth: 48,
                                          artworkHeight: 48,
                                          nullArtworkWidget:
                                              _defaultArtwork(cs),
                                        )
                                      : _defaultArtwork(cs),
                                ),
                                title: Text(song.title,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                  song.artist,
                                  style: TextStyle(
                                      color: cs.onSurface
                                          .withValues(alpha: 0.6)),
                                ),
                                trailing: Icon(Icons.play_circle_fill,
                                    color: cs.primary),
                                onTap: () => _playSong(song),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _defaultArtwork(ColorScheme cs) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cs.primary.withValues(alpha: 0.2),
            cs.tertiary.withValues(alpha: 0.1)
          ],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(Icons.music_note, color: cs.primary),
    );
  }
}
