import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';

const String _musicApiBase = 'https://sokovibe-music-api.onrender.com';

class MusicCatalogScreen extends StatefulWidget {
  const MusicCatalogScreen({super.key});

  @override
  State<MusicCatalogScreen> createState() => _MusicCatalogScreenState();
}

class _MusicCatalogScreenState extends State<MusicCatalogScreen> {
  final _searchController = TextEditingController(text: 'ambient');
  final _player = AudioPlayer();
  String _kind = 'music';
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _results = [];
  String? _playingId;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() => _playing = state.playing);
    });
    _search();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() => _error = 'Andika jina la wimbo, msanii au video.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uri = Uri.parse('$_musicApiBase/api/v1/catalog/search').replace(
        queryParameters: {'q': query, 'kind': _kind},
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) {
        throw Exception('API imerudisha HTTP ${response.statusCode}');
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final items = (body['results'] as List? ?? [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      if (!mounted) return;
      setState(() {
        _results = items;
        if (items.isEmpty) {
          _error = 'Hakuna matokeo yenye leseni wazi yaliyopatikana. Jaribu jina jingine.';
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Imeshindikana kuunganisha huduma ya muziki. Jaribu tena. (${e.toString().replaceFirst('Exception: ', '')})');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String> _resolveStream(Map<String, dynamic> item) async {
    final direct = item['streamUrl']?.toString();
    if (direct != null && direct.startsWith('https://')) return direct;
    final path = item['streamLookupUrl']?.toString();
    if (path == null || !path.startsWith('/api/v1/catalog/play/')) {
      throw Exception('Chanzo hiki hakina kiungo cha playback.');
    }
    final response = await http.get(Uri.parse('$_musicApiBase$path'))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw Exception('Faili ya media haipatikani.');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final url = body['streamUrl']?.toString();
    if (url == null || !url.startsWith('https://')) {
      throw Exception('Hakuna kiungo salama cha playback.');
    }
    return url;
  }

  Future<void> _play(Map<String, dynamic> item) async {
    final id = '${item['provider']}:${item['id']}';
    try {
      if (_playingId == id && _playing) {
        await _player.pause();
        return;
      }
      if (_playingId == id && !_playing) {
        await _player.play();
        return;
      }
      final url = await _resolveStream(item);
      await _player.setUrl(url);
      if (!mounted) return;
      setState(() => _playingId = id);
      await _player.play();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Playback imeshindikana: ${e.toString().replaceFirst('Exception: ', '')}')),
        );
      }
    }
  }

  Future<void> _openSource(String? value) async {
    final url = Uri.tryParse(value ?? '');
    if (url == null || url.scheme != 'https') return;
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('SokoVibe Music'),
        actions: [
          IconButton(
            tooltip: 'Acha muziki',
            onPressed: () async {
              await _player.stop();
              if (mounted) setState(() => _playingId = null);
            },
            icon: const Icon(Icons.stop_circle_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: 'Tafuta wimbo, msanii au video',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  onPressed: _loading ? null : _search,
                  icon: const Icon(Icons.arrow_forward),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'music', label: Text('Muziki'), icon: Icon(Icons.music_note)),
                ButtonSegment(value: 'movie', label: Text('Video'), icon: Icon(Icons.movie_outlined)),
              ],
              selected: {_kind},
              onSelectionChanged: (selected) {
                setState(() => _kind = selected.first);
                _search();
              },
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _error != null && _results.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.library_music_outlined, size: 52, color: colors.primary),
                          const SizedBox(height: 12),
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _loading ? null : _search,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Jaribu tena'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _results.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = _results[index];
                      final id = '${item['provider']}:${item['id']}';
                      final isCurrent = id == _playingId;
                      final image = item['image']?.toString();
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(10),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: 58,
                              height: 58,
                              child: image != null && image.startsWith('https://')
                                  ? Image.network(image, fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => _cover(colors))
                                  : _cover(colors),
                            ),
                          ),
                          title: Text(item['title']?.toString() ?? 'Bila jina', maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item['creator']?.toString() ?? 'Msanii hajatajwa', maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 4),
                                Text(
                                  '${item['provider'] == 'jamendo' ? 'Jamendo' : 'Internet Archive'} • ${item['license'] ?? 'Leseni haijatajwa'}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ],
                            ),
                          ),
                          isThreeLine: true,
                          trailing: IconButton.filledTonal(
                            tooltip: isCurrent && _playing ? 'Sitisha' : 'Cheza',
                            onPressed: () => _play(item),
                            icon: Icon(isCurrent && _playing ? Icons.pause : Icons.play_arrow),
                          ),
                          onTap: () => _openSource(item['sourceUrl']?.toString()),
                        ),
                      );
                    },
                  ),
          ),
          if (_playingId != null)
            SafeArea(
              top: false,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: colors.surfaceContainerHighest,
                child: Row(
                  children: [
                    Icon(_playing ? Icons.graphic_eq : Icons.pause_circle_outline, color: colors.primary),
                    const SizedBox(width: 10),
                    const Expanded(child: Text('SokoVibe Music • playback')),
                    IconButton(
                      onPressed: () => _playing ? _player.pause() : _player.play(),
                      icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _cover(ColorScheme colors) => Container(
    color: colors.primaryContainer,
    alignment: Alignment.center,
    child: Icon(Icons.music_note, color: colors.onPrimaryContainer, size: 28),
  );
}
