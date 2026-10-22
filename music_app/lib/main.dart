import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'models/music_track.dart';
import 'services/music_api.dart';
import 'services/notification_service.dart';
import 'services/lyrics_service.dart';
import 'services/app_settings.dart';
import 'services/offline_music_service.dart';
import 'screens/music_admin_dashboard_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.initialize();
  runApp(const SokoVibeMusicApp());
}

class SokoVibeMusicApp extends StatefulWidget {
  const SokoVibeMusicApp({super.key});

  @override
  State<SokoVibeMusicApp> createState() => _SokoVibeMusicAppState();
}

class _SokoVibeMusicAppState extends State<SokoVibeMusicApp> {
  final settings = AppSettings();
  bool ready = false;

  @override
  void initState() {
    super.initState();
    settings.load().then((_) {
      if (mounted) setState(() => ready = true);
    });
  }

  void refreshSettings() => setState(() {});

  @override
  Widget build(BuildContext context) {
    if (!ready) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('en'),
        supportedLocales: const [Locale('en')],
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.green),
        home: const _SokoLoadingScreen(message: 'Preparing your music'),
      );
    }
    final seed = Color(settings.colorSeed);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('en'),
      supportedLocales: const [Locale('en')],
      title: 'Soko Vibe Music',
      themeMode: settings.themeMode,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: seed, brightness: Brightness.light),
      darkTheme: ThemeData(useMaterial3: true, colorSchemeSeed: seed, brightness: Brightness.dark),
      home: MusicHomePage(settings: settings, onSettingsChanged: refreshSettings),
    );
  }
}


class _SokoLoadingScreen extends StatefulWidget {
  const _SokoLoadingScreen({required this.message});
  final String message;

  @override
  State<_SokoLoadingScreen> createState() => _SokoLoadingScreenState();
}

class _SokoLoadingScreenState extends State<_SokoLoadingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 1250),
  )..repeat();

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (_, __) => Transform.rotate(
            angle: _controller.value * 6.28318,
            child: Container(
              width: 84, height: 84,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: LinearGradient(colors: [scheme.primary, const Color(0xFF00D985)]),
                boxShadow: [BoxShadow(color: scheme.primary.withValues(alpha: .25), blurRadius: 24)],
              ),
              child: const Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 48),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('SokoVibe Music', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(widget.message, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 20),
        SizedBox(width: 130, child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: const LinearProgressIndicator(minHeight: 4),
        )),
      ])),
    );
  }
}

class _MusicLoadingStrip extends StatefulWidget {
  const _MusicLoadingStrip();
  @override
  State<_MusicLoadingStrip> createState() => _MusicLoadingStripState();
}

class _MusicLoadingStripState extends State<_MusicLoadingStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 900),
  )..repeat();
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (_, __) => LinearProgressIndicator(
      minHeight: 3,
      value: null,
      color: Color.lerp(Theme.of(context).colorScheme.primary, const Color(0xFF00D985), _controller.value),
    ),
  );
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();
  @override
  Widget build(BuildContext context) => Container(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    alignment: Alignment.center,
    child: Icon(Icons.graphic_eq_rounded, color: Theme.of(context).colorScheme.primary, size: 30),
  );
}


class _PressScale extends StatefulWidget {
  const _PressScale({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;
  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _pressed = false;
  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }
  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTapDown: (_) => _setPressed(true),
    onTapUp: (_) => _setPressed(false),
    onTapCancel: () => _setPressed(false),
    onTap: widget.onTap,
    child: AnimatedScale(
      scale: _pressed ? .975 : 1,
      duration: Duration(milliseconds: _pressed ? 80 : 180),
      curve: Curves.easeOutCubic,
      child: widget.child,
    ),
  );
}

class _EmptyMusicState extends StatefulWidget {
  const _EmptyMusicState({super.key});
  @override
  State<_EmptyMusicState> createState() => _EmptyMusicStateState();
}

class _EmptyMusicStateState extends State<_EmptyMusicState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 1900),
  )..repeat(reverse: true);
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (_, child) => Transform.translate(
              offset: Offset(0, -7 * _controller.value),
              child: Transform.rotate(
                angle: (_controller.value - .5) * .08,
                child: child,
              ),
            ),
            child: SizedBox(
              width: 150, height: 150,
              child: Stack(alignment: Alignment.center, children: [
                Container(
                  width: 142, height: 142,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [scheme.primaryContainer, scheme.surfaceContainerHighest],
                    ),
                  ),
                ),
                Icon(Icons.album_rounded, size: 104,
                  color: scheme.primary.withValues(alpha: .26)),
                Container(
                  width: 62, height: 62,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle, color: scheme.primary,
                    boxShadow: [BoxShadow(
                      color: scheme.primary.withValues(alpha: .24),
                      blurRadius: 18, spreadRadius: 2,
                    )],
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 42),
                ),
                Positioned(top: 10, right: 10,
                  child: Icon(Icons.auto_awesome_rounded, color: scheme.tertiary, size: 26)),
                Positioned(bottom: 14, left: 8,
                  child: Icon(Icons.music_note_rounded, color: scheme.primary, size: 27)),
              ]),
            ),
          ),
          const SizedBox(height: 22),
          Text('Discover',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }
}

class _SearchLoadingState extends StatefulWidget {
  const _SearchLoadingState({super.key});
  @override
  State<_SearchLoadingState> createState() => _SearchLoadingStateState();
}

class _SearchLoadingStateState extends State<_SearchLoadingState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 1100),
  )..repeat();
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      AnimatedBuilder(
        animation: _controller,
        builder: (_, __) => Row(mainAxisSize: MainAxisSize.min, children: List.generate(5, (index) {
          final phase = (_controller.value * 2 * math.pi) + index * .8;
          final height = 16 + (22 * ((1 + math.sin(phase)) / 2));
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: 7, height: height,
            decoration: BoxDecoration(
              color: Color.lerp(scheme.primary, const Color(0xFF00D985), index / 4),
              borderRadius: BorderRadius.circular(8),
            ),
          );
        })),
      ),
      const SizedBox(height: 8),
    ]));
  }
}

class _DownloadProgressDialog extends StatefulWidget {
  const _DownloadProgressDialog({required this.track});
  final MusicTrack track;
  @override
  State<_DownloadProgressDialog> createState() => _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 1000),
  )..repeat();
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      AnimatedBuilder(
        animation: _controller,
        builder: (_, __) => Transform.rotate(
          angle: _controller.value * 6.28318,
          child: Container(
            width: 68, height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Theme.of(context).colorScheme.primary, width: 5),
            ),
            child: Icon(Icons.download_rounded, color: Theme.of(context).colorScheme.primary, size: 34),
          ),
        ),
      ),
      const SizedBox(height: 18),
      Text('Downloading music…', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      Text(widget.track.title, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
      const SizedBox(height: 16),
      const LinearProgressIndicator(),
      const SizedBox(height: 8),
      Text('Keeping this track ready for offline listening', style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
    ]),
  );
}

class MusicHomePage extends StatefulWidget {
  const MusicHomePage({super.key, required this.settings, required this.onSettingsChanged});
  final AppSettings settings;
  final VoidCallback onSettingsChanged;
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
  void initState() {
    super.initState();
    _setupNotifications();
  }

  Future<void> _setupNotifications() async {
    if (!widget.settings.dailyReminder) return;
    final granted = await NotificationService.instance.requestPermission();
    if (granted) {
      await NotificationService.instance.scheduleDailyReminder(
        hour: widget.settings.reminderHour,
        minute: widget.settings.reminderMinute,
      );
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
    } catch (e) {
      if (mounted) setState(() => error = 'Search failed: $e');
      await NotificationService.instance.showImportant(
        id: 2010,
        title: 'Music search failed',
        body: e.toString().length > 160 ? '${e.toString().substring(0, 160)}…' : e.toString(),
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Playback failed: $e')),
        );
      }
      await NotificationService.instance.notifyPlaybackFailed();
    }
  }

  Future<void> downloadTrack(MusicTrack track) async {
    if (!track.canDownload || track.downloadUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Jamendo does not permit downloading this track.')),
      );
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save for offline listening?'),
        content: Text(
          'Jamendo marks this track as downloadable. Review its license before saving it offline. License: ${track.license}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue')),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    var progressDialogShown = false;
    try {
      progressDialogShown = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _DownloadProgressDialog(track: track),
      );
      await OfflineMusicService().download(track);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Row(children: [
            const Icon(Icons.check_circle, color: Colors.greenAccent),
            const SizedBox(width: 10),
            Expanded(child: Text('Saved “${track.title}” for offline listening.')),
          ]),
        ),
      );
      await NotificationService.instance.notifyDownloadComplete(track.title);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $error')),
      );
    } finally {
      if (progressDialogShown && mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> loadRecommendations() async {
    setState(() { loading = true; error = null; });
    try {
      final results = await api.recommend(
        mood: 'discover',
        genre: 'afrobeat',
        limit: 20,
      );
      if (!mounted) return;
      setState(() => tracks = results);
      if (results.isEmpty) {
        setState(() => error = 'No recommendations are available right now.');
      }
    } catch (e) {
      if (mounted) setState(() => error = 'Recommendations failed: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> showAiLyrics() async {
    final themeController = TextEditingController();
    String genre = 'afrobeat';
    String language = 'English';
    bool generating = false;
    String? generated;
    String? failure;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('AI Lyrics Studio'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: themeController,
                    enabled: !generating,
                    maxLength: 180,
                    decoration: const InputDecoration(
                      labelText: 'Song theme',
                      hintText: 'Hope, love, a new beginning…',
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: genre,
                    decoration: const InputDecoration(labelText: 'Genre'),
                    items: const ['afrobeat', 'bongo flava', 'gospel', 'hip hop', 'acoustic']
                        .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                        .toList(),
                    onChanged: generating ? null : (value) {
                      if (value != null) setDialogState(() => genre = value);
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: language,
                    decoration: const InputDecoration(labelText: 'Language'),
                    items: const ['English', 'Swahili']
                        .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                        .toList(),
                    onChanged: generating ? null : (value) {
                      if (value != null) setDialogState(() => language = value);
                    },
                  ),
                  if (generating) const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: LinearProgressIndicator(),
                  ),
                  if (failure != null) Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(failure!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                  if (generated != null) ...[
                    const Divider(height: 24),
                    SelectableText(generated!, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5)),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            const SnackBar(content: Text('Select the generated lyrics to copy them.')),
                          );
                        },
                        icon: const Icon(Icons.text_fields),
                        label: const Text('Lyrics generated'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: generating ? null : () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              onPressed: generating ? null : () async {
                if (themeController.text.trim().isEmpty) {
                  setDialogState(() => failure = 'Enter a song theme first.');
                  return;
                }
                setDialogState(() { generating = true; failure = null; generated = null; });
                try {
                  final lyrics = await api.generateLyrics(
                    theme: themeController.text.trim(),
                    genre: genre,
                    language: language,
                  );
                  if (dialogContext.mounted) setDialogState(() => generated = lyrics);
                } catch (e) {
                  if (dialogContext.mounted) setDialogState(() => failure = 'Lyrics generation failed: $e');
                } finally {
                  if (dialogContext.mounted) setDialogState(() => generating = false);
                }
              },
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Generate'),
            ),
          ],
        ),
      ),
    );
    themeController.dispose();
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


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Soko Vibe Music'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'AI Lyrics Studio',
            onPressed: showAiLyrics,
            icon: const Icon(Icons.lyrics_outlined),
          ),
          IconButton(
            tooltip: 'Discover recommendations',
            onPressed: loadRecommendations,
            icon: const Icon(Icons.auto_awesome_outlined),
          ),
          IconButton(
            tooltip: 'Backend diagnostics',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => MusicAdminDashboardPage(api: api),
            )),
            icon: const Icon(Icons.monitor_heart_outlined),
          ),
          IconButton(
            tooltip: 'Offline library',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => OfflineLibraryPage(player: player),
            )),
            icon: const Icon(Icons.library_music_outlined),
          ),
          IconButton(
            tooltip: 'App settings',
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => AppSettingsPage(
                  settings: widget.settings,
                  onChanged: widget.onSettingsChanged,
                ),
              ));
              if (mounted) setState(() {});
            },
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: SearchBar(
              controller: searchController,
              hintText: 'Search music',
              leading: const Icon(Icons.search),
              trailing: [IconButton(onPressed: search, icon: const Icon(Icons.arrow_forward))],
              onSubmitted: (_) => search(),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 12, bottom: 4),
              child: IconButton.filledTonal(
                tooltip: 'On-device music',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => OfflineLibraryPage(player: player),
                )),
                icon: const Icon(Icons.phone_android_rounded),
              ),
            ),
          ),
          if (loading && tracks.isNotEmpty) const _MusicLoadingStrip(),
          if (error != null) Padding(padding: const EdgeInsets.all(16), child: Text(error!)),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 360),
              reverseDuration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, .025), end: Offset.zero).animate(animation),
                  child: child,
                ),
              ),
              child: loading && tracks.isEmpty
                  ? const _SearchLoadingState(key: ValueKey('loading'))
                  : tracks.isEmpty
                      ? const _EmptyMusicState(key: ValueKey('empty'))
                      : ListView.builder(
                          key: const ValueKey('results'),
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                          itemCount: tracks.length,
                          itemBuilder: (_, i) {
                            final track = tracks[i];
                            return TweenAnimationBuilder<double>(
                              key: ValueKey('${track.id}-$i'),
                              tween: Tween(begin: 0, end: 1),
                              duration: Duration(milliseconds: 240 + ((i > 8 ? 8 : i) * 45)),
                              curve: Curves.easeOutCubic,
                              builder: (context, value, child) => Opacity(
                                opacity: value,
                                child: Transform.translate(
                                  offset: Offset(0, 14 * (1 - value)),
                                  child: child,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _PressScale(
                                  onTap: () => play(track),
                                  child: Card(
                                    margin: EdgeInsets.zero,
                                    clipBehavior: Clip.antiAlias,
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                      leading: ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: SizedBox(
                                          width: 58, height: 58,
                                          child: track.image.isEmpty
                                              ? const _CoverPlaceholder()
                                              : CachedNetworkImage(
                                                  imageUrl: track.image,
                                                  width: 58, height: 58,
                                                  fit: BoxFit.cover,
                                                  placeholder: (_, __) => const _CoverPlaceholder(),
                                                  errorWidget: (_, __, ___) => const _CoverPlaceholder(),
                                                ),
                                        ),
                                      ),
                                      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                                      subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                                      trailing: Wrap(spacing: 0, children: [
                                        if (track.canDownload)
                                          IconButton(
                                            tooltip: 'Download for offline',
                                            onPressed: () => downloadTrack(track),
                                            icon: const Icon(Icons.download_for_offline_outlined),
                                          ),
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
                                      ]),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ),
          if (current != null) _PlayerBar(track: current!, player: player),
        ]),
      ),
    );
  }
}

class AppSettingsPage extends StatefulWidget {
  const AppSettingsPage({super.key, required this.settings, required this.onChanged});
  final AppSettings settings;
  final VoidCallback onChanged;

  @override
  State<AppSettingsPage> createState() => _AppSettingsPageState();
}

class _AppSettingsPageState extends State<AppSettingsPage> {
  static const colors = <int>[
    0xFF2E7D32, 0xFF00897B, 0xFF1565C0, 0xFF6A1B9A,
    0xFFEF6C00, 0xFFC62828, 0xFF37474F,
  ];
  Future<void> _changeReminder(bool enabled) async {
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
      await widget.settings.saveReminder(true);
      await NotificationService.instance.scheduleDailyReminder(
        hour: widget.settings.reminderHour,
        minute: widget.settings.reminderMinute,
      );
    } else {
      await widget.settings.saveReminder(false);
      await NotificationService.instance.cancelDailyReminder();
    }
    if (mounted) setState(() {});
    widget.onChanged();
  }

  Future<void> _chooseReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: widget.settings.reminderHour, minute: widget.settings.reminderMinute),
    );
    if (picked == null) return;
    await widget.settings.saveReminderTime(picked.hour, picked.minute);
    if (widget.settings.dailyReminder) {
      await NotificationService.instance.scheduleDailyReminder(hour: picked.hour, minute: picked.minute);
    }
    if (mounted) setState(() {});
  }

  Future<void> _chooseTheme(ThemeMode? mode) async {
    if (mode == null) return;
    await widget.settings.saveTheme(mode);
    if (mounted) setState(() {});
    widget.onChanged();
  }

  Future<void> _chooseColor(int color) async {
    await widget.settings.saveColor(color);
    if (mounted) setState(() {});
    widget.onChanged();
  }

  String _timeLabel(BuildContext context) => TimeOfDay(
    hour: widget.settings.reminderHour,
    minute: widget.settings.reminderMinute,
  ).format(context);

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('App settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Text('Appearance', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Theme'),
                const SizedBox(height: 8),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.settings_suggest_outlined), label: Text('System')),
                    ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Light')),
                    ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Dark')),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (selection) => _chooseTheme(selection.first),
                ),
                const SizedBox(height: 20),
                const Text('Accent colour'),
                const SizedBox(height: 12),
                Wrap(spacing: 12, runSpacing: 12, children: [
                  for (final color in colors)
                    InkWell(
                      onTap: () => _chooseColor(color),
                      customBorder: const CircleBorder(),
                      child: Semantics(
                        label: 'Choose accent colour',
                        child: CircleAvatar(
                          radius: 22,
                          backgroundColor: Color(color),
                          child: settings.colorSeed == color
                              ? const Icon(Icons.check, color: Colors.white)
                              : null,
                        ),
                      ),
                    ),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 20),
          Text('Notifications', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(children: [
              SwitchListTile(
                secondary: const Icon(Icons.notifications_active_outlined),
                title: const Text('Daily listening reminder'),
                subtitle: const Text('A gentle reminder to play music each day'),
                value: settings.dailyReminder,
                onChanged: _changeReminder,
              ),
              const Divider(height: 1),
              ListTile(
                enabled: settings.dailyReminder,
                leading: const Icon(Icons.schedule),
                title: const Text('Reminder time'),
                subtitle: Text(_timeLabel(context)),
                trailing: const Icon(Icons.chevron_right),
                onTap: settings.dailyReminder ? _chooseReminderTime : null,
              ),
            ]),
          ),
          const SizedBox(height: 20),
          if (const bool.fromEnvironment('ENABLE_ADMIN_DASHBOARD', defaultValue: false)) ...[
            Text('Administration', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: const Text('Music admin dashboard'),
                subtitle: const Text('Check backend health and music endpoints'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => MusicAdminDashboardPage(api: MusicApi()),
                )),
              ),
            ),
            const SizedBox(height: 20),
          ],
          Text('About', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(child: Column(children: [
            const ListTile(
              leading: Icon(Icons.music_note),
              title: Text('Soko Vibe Music'),
              subtitle: Text('Music discovery, player and lyrics'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('App version'),
              subtitle: const Text('0.2.0'),
              onTap: () => showAboutDialog(
                context: context,
                applicationName: 'Soko Vibe Music',
                applicationVersion: '0.2.0',
                applicationLegalese: 'Made for music discovery.',
              ),
            ),
          ])),
          const SizedBox(height: 12),
          Text(
            'Settings are saved on this device. Music search and lyrics need an internet connection; imported or permitted downloaded tracks can be played offline.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
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
                                      if (timedLines[i].time <= position) {
                                        activeIndex = i;
                                      } else {
                                        break;
                                      }
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

class OfflineLibraryPage extends StatefulWidget {
  const OfflineLibraryPage({super.key, required this.player});
  final AudioPlayer player;

  @override
  State<OfflineLibraryPage> createState() => _OfflineLibraryPageState();
}

class _OfflineLibraryPageState extends State<OfflineLibraryPage> {
  final service = OfflineMusicService();
  List<OfflineTrack> tracks = <OfflineTrack>[];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() { loading = true; error = null; });
    try {
      final result = await service.list();
      if (mounted) setState(() => tracks = result);
    } catch (_) {
      if (mounted) setState(() => error = 'Could not load your offline music.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _import() async {
    try {
      await service.importLocalAudio();
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not import audio: $e')),
        );
      }
    }
  }

  Future<void> _play(OfflineTrack track) async {
    try {
      await widget.player.setFilePath(track.path);
      await widget.player.play();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This local audio file could not be played.')),
        );
      }
    }
  }

  Future<void> _remove(OfflineTrack track) async {
    await service.remove(track);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline music'),
        actions: [
          IconButton(
            tooltip: 'Import audio from device',
            onPressed: _import,
            icon: const Icon(Icons.add_to_photos_outlined),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Text(error!))
              : tracks.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.library_music_outlined, size: 56),
                            const SizedBox(height: 12),
                            const Text('No offline music yet'),
                            const SizedBox(height: 8),
                            const Text('Download eligible tracks or import audio files from your device.'),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: _import,
                              icon: const Icon(Icons.audio_file_outlined),
                              label: const Text('Import local music'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _reload,
                      child: ListView.builder(
                        itemCount: tracks.length,
                        itemBuilder: (context, index) {
                          final track = tracks[index];
                          return ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.music_note)),
                            title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text('${track.artist} · ${track.source}'),
                            onTap: () => _play(track),
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'play') _play(track);
                                if (value == 'remove') _remove(track);
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'play', child: Text('Play offline')),
                                PopupMenuItem(value: 'remove', child: Text('Remove from offline library')),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

class _PlaybackWaveform extends StatefulWidget {
  const _PlaybackWaveform({required this.playing, required this.color});

  final bool playing;
  final Color color;

  @override
  State<_PlaybackWaveform> createState() => _PlaybackWaveformState();
}

class _PlaybackWaveformState extends State<_PlaybackWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  );

  @override
  void initState() {
    super.initState();
    if (widget.playing) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _PlaybackWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.playing && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 18,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(19, (index) {
              final phase = (index * 0.72) + (_controller.value * 2 * math.pi);
              final wave = (math.sin(phase) + 1) / 2;
              final height = widget.playing ? 3.0 + wave * 14.0 : 3.0 + (index % 4) * 1.5;
              return Container(
                width: 3,
                height: height,
                margin: const EdgeInsets.only(right: 2),
                decoration: BoxDecoration(
                  color: widget.color.withValues(
                    alpha: widget.playing ? 0.55 + wave * 0.45 : 0.35,
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          );
        },
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
            ClipRRect(borderRadius: BorderRadius.circular(8), child: track.image.isEmpty ? const Icon(Icons.music_note, size: 32) : CachedNetworkImage(imageUrl: track.image, width: 48, height: 48, fit: BoxFit.cover, errorWidget: (_, __, ___) => const Icon(Icons.music_note))),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(track.artist, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 5),
                  StreamBuilder<PlayerState>(
                    stream: player.playerStateStream,
                    initialData: player.playerState,
                    builder: (context, snapshot) {
                      final playing = snapshot.data?.playing ?? false;
                      return _PlaybackWaveform(
                        playing: playing,
                        color: Theme.of(context).colorScheme.primary,
                      );
                    },
                  ),
                ],
              ),
            ),
            StreamBuilder<PlayerState>(
              stream: player.playerStateStream,
              initialData: player.playerState,
              builder: (_, snap) {
                final playing = snap.data?.playing ?? false;
                return IconButton(
                  tooltip: playing ? 'Pause' : 'Play',
                  onPressed: () => playing ? player.pause() : player.play(),
                  icon: Icon(
                    playing ? Icons.pause_circle : Icons.play_circle,
                    size: 34,
                  ),
                );
              },
            ),
          ]),
        ),
      ),
    );
  }
}
