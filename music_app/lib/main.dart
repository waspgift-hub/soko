import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'models/music_track.dart';
import 'services/music_api.dart';
import 'services/notification_service.dart';
import 'services/lyrics_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.initialize();
  runApp(const SokoVibeMusicApp());
}

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
  bool reminderEnabled = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _setupNotifications();
  }

  Future<void> _setupNotifications() async {
    final granted = await NotificationService.instance.requestPermission();
    if (granted) {
      await NotificationService.instance.scheduleDailyReminder(hour: 19);
    } else {
      if (mounted) setState(() => reminderEnabled = false);
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    player.dispose();
    super.dispose();
  }

  Future<void> search() async {
    if (searchController.text.trim().isEmpty) {
      setState(() => error = 'Enter a song, artist or album name first.');
      return;
    }
    setState(() { loading = true; error = null; });
    try {
      final results = await api.search(searchController.text.trim());
      if (mounted) setState(() => tracks = results);
    } catch (_) {
      if (mounted) setState(() => error = 'Search failed. Check your connection or API.');
      await NotificationService.instance.showImportant(
        id: 2010,
        title: 'Music search failed',
        body: 'Check your internet connection and try again.',
        payload: 'retry_search',
      );
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This track could not be played.')),
        );
      }
      await NotificationService.instance.notifyPlaybackFailed();
    }
  }

  void showLyrics(MusicTrack track) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _LyricsSheet(track: track, player: player),
    );
  }

  Future<void> _toggleReminder(bool enabled) async {
    if (enabled) {
      final granted = await NotificationService.instance.requestPermission();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Allow notifications in Android settings to enable reminders.')),
          );
        }
        return;
      }
      await NotificationService.instance.scheduleDailyReminder(hour: 19);
    } else {
      await NotificationService.instance.cancelDailyReminder();
    }
    if (mounted) setState(() => reminderEnabled = enabled);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Soko Vibe Music'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Notification settings',
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              builder: (context) => SafeArea(
                child: SwitchListTile(
                  secondary: const Icon(Icons.notifications_active_outlined),
                  title: const Text('Daily listening reminder'),
                  subtitle: const Text('Every day at about 7:00 PM'),
                  value: reminderEnabled,
                  onChanged: (value) {
                    Navigator.pop(context);
                    _toggleReminder(value);
                  },
                ),
              ),
            ),
            icon: const Icon(Icons.notifications_outlined),
          ),
        ],
      ),
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
                            child: CachedNetworkImage(
                              imageUrl: track.image,
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => const Icon(Icons.music_note),
                            ),
                          ),
                          title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: Wrap(
                            spacing: 0,
                            children: [
                              IconButton(
                                tooltip: 'Show lyrics',
                                onPressed: () => showLyrics(track),
                                icon: const Icon(Icons.lyrics_outlined),
                              ),
                              IconButton(
                                tooltip: 'Play',
                                onPressed: () => play(track),
                                icon: const Icon(Icons.play_circle_fill),
                              ),
                            ],
                          ),
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

class _LyricsSheet extends StatefulWidget {
  const _LyricsSheet({required this.track, required this.player});
  final MusicTrack track;
  final AudioPlayer player;

  @override
  State<_LyricsSheet> createState() => _LyricsSheetState();
}

class _LyricsSheetState extends State<_LyricsSheet> {
  final _service = LyricsService();
  TrackLyrics? _lyrics;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLyrics();
  }

  Future<void> _loadLyrics() async {
    try {
      final result = await _service.findLyrics(
        title: widget.track.title,
        artist: widget.track.artist,
      );
      if (!mounted) return;
      setState(() {
        _lyrics = result;
        _loading = false;
        if (result == null) _error = 'Lyrics are not available for this song yet.';
      });
    } on LyricsException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _error = 'Unable to load lyrics right now.'; _loading = false; });
    }
  }

  List<_TimedLyricLine> _parseSyncedLyrics(String raw) {
    final lines = <_TimedLyricLine>[];
    final pattern = RegExp(r'^\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]\s*(.*)$');
    for (final line in raw.split('\n')) {
      final match = pattern.firstMatch(line.trim());
      if (match == null) continue;
      final minutes = int.tryParse(match.group(1) ?? '') ?? 0;
      final seconds = int.tryParse(match.group(2) ?? '') ?? 0;
      final fractionRaw = match.group(3) ?? '0';
      final millis = int.tryParse(fractionRaw.padRight(3, '0').substring(0, 3)) ?? 0;
      lines.add(_TimedLyricLine(
        time: Duration(minutes: minutes, seconds: seconds, milliseconds: millis),
        text: match.group(4) ?? '',
      ));
    }
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = _lyrics;
    final synced = lyrics?.syncedLyrics;
    final timedLines = synced == null ? <_TimedLyricLine>[] : _parseSyncedLyrics(synced);
    final plain = lyrics?.plainLyrics;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.82,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Lyrics', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text('${widget.track.title} • ${widget.track.artist}',
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium),
            const Divider(height: 24),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.lyrics_outlined, size: 42),
                            const SizedBox(height: 12),
                            Text(_error!, textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: () {
                                setState(() { _loading = true; _error = null; });
                                _loadLyrics();
                              },
                              icon: const Icon(Icons.refresh),
                              label: const Text('Try again'),
                            ),
                          ],
                        ))
                      : lyrics?.instrumental == true
                          ? const Center(child: Text('This track is marked as instrumental.'))
                          : timedLines.isNotEmpty
                              ? StreamBuilder<Duration>(
                                  stream: widget.player.positionStream,
                                  initialData: widget.player.position,
                                  builder: (context, snapshot) {
                                    final position = snapshot.data ?? Duration.zero;
                                    var activeIndex = -1;
                                    for (var i = 0; i < timedLines.length; i++) {
                                      if (timedLines[i].time <= position) activeIndex = i;
                                      else break;
                                    }
                                    return ListView.builder(
                                      itemCount: timedLines.length,
                                      itemBuilder: (context, index) {
                                        final active = index == activeIndex;
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 9),
                                          child: AnimatedDefaultTextStyle(
                                            duration: const Duration(milliseconds: 160),
                                            style: Theme.of(context).textTheme.titleMedium!.copyWith(
                                              height: 1.45,
                                              fontWeight: active ? FontWeight.bold : FontWeight.normal,
                                              color: active
                                                  ? Theme.of(context).colorScheme.primary
                                                  : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.72),
                                            ),
                                            child: Text(timedLines[index].text),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                )
                              : (plain != null && plain.trim().isNotEmpty)
                                  ? SingleChildScrollView(
                                      child: SelectableText(plain, style: Theme.of(context).textTheme.titleMedium?.copyWith(height: 1.7)),
                                    )
                                  : const Center(child: Text('Lyrics are not available for this song yet.')),
            ),
            const SizedBox(height: 8),
            Text(
              'Lyrics provided by LRCLIB. Availability and timing depend on the source record.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _TimedLyricLine {
  const _TimedLyricLine({required this.time, required this.text});
  final Duration time;
  final String text;
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
            ClipRRect(borderRadius: BorderRadius.circular(8), child: CachedNetworkImage(imageUrl: track.image, width: 48, height: 48, fit: BoxFit.cover, errorWidget: (_, __, ___) => const Icon(Icons.music_note))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(track.artist, style: Theme.of(context).textTheme.bodySmall),
            ])),
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
