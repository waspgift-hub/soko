import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'models/music_track.dart';
import 'services/music_api.dart';

void main() => runApp(const SokoVibeMusicApp());

class SokoVibeMusicApp extends StatelessWidget {
  const SokoVibeMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Soko Vibe Music',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.green),
      home: const MusicHomePage(),
    );
  }
}

class MusicHomePage extends StatefulWidget {
  const MusicHomePage({super.key});
  @override
  State<MusicHomePage> createState() => _MusicHomePageState();
}

class _MusicHomePageState extends State<MusicHomePage> {
  final api = MusicApi();
  final player = AudioPlayer();
  final searchController = TextEditingController();
  List<MusicTrack> tracks = [];
  MusicTrack? current;
  bool loading = false;
  String? error;

  @override
  void dispose() {
    searchController.dispose();
    player.dispose();
    super.dispose();
  }

  Future<void> search() async {
    setState(() { loading = true; error = null; });
    try {
      final results = await api.search(searchController.text);
      setState(() => tracks = results);
    } catch (e) {
      setState(() => error = 'Search failed. Check your connection or API.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> play(MusicTrack track) async {
    try {
      setState(() => current = track);
      final url = await api.playUrl(track.id);
      await player.setUrl(url);
      await player.play();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This track could not be played.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Soko Vibe Music'), centerTitle: false),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: SearchBar(
              controller: searchController,
              hintText: 'Search songs, artists or albums',
              leading: const Icon(Icons.search),
              trailing: [IconButton(onPressed: search, icon: const Icon(Icons.arrow_forward))],
              onSubmitted: (_) => search(),
            ),
          ),
          if (loading) const LinearProgressIndicator(minHeight: 2),
          if (error != null) Padding(padding: const EdgeInsets.all(16), child: Text(error!)),
          Expanded(
            child: tracks.isEmpty
                ? const Center(child: Text('Search for music to get started'))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: tracks.length,
                    itemBuilder: (_, i) {
                      final track = tracks[i];
                      return Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(8),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: CachedNetworkImage(imageUrl: track.image, width: 56, height: 56, fit: BoxFit.cover, errorWidget: (_, __, ___) => const Icon(Icons.music_note)),
                          ),
                          title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: IconButton(onPressed: () => play(track), icon: const Icon(Icons.play_circle_fill)),
                        ),
                      );
                    },
                  ),
          ),
          if (current != null) _PlayerBar(track: current!, player: player),
        ]),
      ),
    );
  }
}

class _PlayerBar extends StatelessWidget {
  const _PlayerBar({required this.track, required this.player});
  final MusicTrack track;
  final AudioPlayer player;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            ClipRRect(borderRadius: BorderRadius.circular(8), child: CachedNetworkImage(imageUrl: track.image, width: 48, height: 48, fit: BoxFit.cover)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis), Text(track.artist, style: Theme.of(context).textTheme.bodySmall)])),
            StreamBuilder<PlayerState>(
              stream: player.playerStateStream,
              builder: (_, snap) {
                final playing = snap.data?.playing ?? false;
                return IconButton(onPressed: () => playing ? player.pause() : player.play(), icon: Icon(playing ? Icons.pause_circle : Icons.play_circle, size: 34));
              },
            ),
          ]),
        ),
      ),
    );
  }
}
