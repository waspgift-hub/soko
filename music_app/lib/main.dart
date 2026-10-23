import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'models/music_track.dart';
import 'services/music_api.dart';
import 'services/youtube_search_service.dart';
import 'services/notification_service.dart';
import 'services/lyrics_service.dart';
import 'services/app_settings.dart';
import 'services/auth_service.dart';
import 'services/sound_identity.dart';
import 'services/download_service.dart';

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
    settings.load().then((_) async {
      if (!mounted) return;
      setState(() => ready = true);
      await SoundIdentity.instance.playStartupOnce(enabled: settings.startupSound);
    });
  }

  void refreshSettings() => setState(() {});

  @override
  Widget build(BuildContext context) {
    if (!ready) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.green),
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    final seed = Color(settings.colorSeed);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Soko Vibe Music',
      themeMode: settings.themeMode,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: seed, brightness: Brightness.light, visualDensity: VisualDensity.standard),
      darkTheme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFFB8F36B), brightness: Brightness.dark, visualDensity: VisualDensity.standard, scaffoldBackgroundColor: const Color(0xFF0B1110), cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero)),
      home: MusicHomePage(settings: settings, onSettingsChanged: refreshSettings),
    );
  }
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
  final youtubeApi = YoutubeSearchService();
  String _searchSource = 'licensed';
  final player = AudioPlayer();
  final searchController = TextEditingController();
  List<MusicTrack> tracks = [];
  List<PlatformFile> _deviceSongs = [];
  MusicTrack? current;
  bool loading = false;
  bool _hasSearched = false;
  int _searchRequestId = 0;
  String? error;
  final Set<String> _downloading = <String>{};
  bool _guestMode = false;
  String? _accountEmail;

  Future<void> _showAccountOptions() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.account_circle_rounded, size: 42),
        title: const Text('Your SokoVibe account'),
        content: Text(_accountEmail != null
            ? 'Signed in as $_accountEmail'
            : _guestMode
                ? 'You are using Guest mode. Your local app features remain available.'
                : 'Sign in to connect your music experience to your Google account, or continue as a guest.'),
        actions: [
          if (_accountEmail != null)
            TextButton(onPressed: () async {
              await AuthService.instance.signOut();
              if (!mounted) return;
              setState(() { _accountEmail = null; _guestMode = false; });
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
            }, child: const Text('Sign out')),
          TextButton(onPressed: () {
            setState(() => _guestMode = true);
            Navigator.pop(dialogContext);
          }, child: const Text('Continue as guest')),
          FilledButton.icon(
            onPressed: () async {
              try {
                final credential = await AuthService.instance.signInWithGoogle();
                if (!mounted) return;
                setState(() {
                  _accountEmail = credential.user?.email;
                  _guestMode = false;
                });
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Google sign-in successful.')),
                  );
                }
              } catch (error) {
                if (!dialogContext.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
                );
              }
            },
            icon: const Icon(Icons.login_rounded),
            label: const Text('Continue with Google'),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _setupNotifications();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final user = await AuthService.instance.restoreSession();
    if (!mounted || user == null) return;
    setState(() {
      _accountEmail = user.email;
      _guestMode = false;
    });
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
    api.close();
    youtubeApi.close();
    player.dispose();
    super.dispose();
  }

  String _tr(String key) {
    const translations = <String, Map<String, String>>{
      'sw': {'FEEL EVERY VIBE':'HISI KILA MUDA','Your sound. Your mood.':'Muziki wako. Hisia zako.','Music that moves you':'Muziki unaokuvutia','Search songs or artists':'Tafuta nyimbo au wasanii','Licensed audio':'Muziki wenye leseni','On-device songs':'Nyimbo za simu','Choose songs':'Chagua nyimbo','No songs selected':'Bado hujachagua nyimbo','Choose your vibe':'Chagua hisia zako','Happy':'Furaha','Chill':'Utulivu','Energy':'Nguvu','Love':'Mapenzi','How to use':'Jinsi ya kutumia','Search and play licensed music, watch YouTube in-app, or choose audio files stored on your phone.':'Tafuta muziki wenye leseni, tazama YouTube ndani ya app, au chagua nyimbo kwenye simu.','Music service is unavailable right now. Your internet may still be working—try again.':'Huduma ya muziki haipatikani sasa. Intaneti yako inaweza kuwa inafanya kazi; jaribu tena.'},
      'fr': {'FEEL EVERY VIBE':'VIVEZ CHAQUE VIBE','Your sound. Your mood.':'Votre son. Votre humeur.','Music that moves you':'La musique qui vous anime','Search songs or artists':'Rechercher titres ou artistes','Licensed audio':'Audio sous licence','On-device songs':'Musique du téléphone','Choose songs':'Choisir des titres','No songs selected':'Aucun titre sélectionné','Choose your vibe':'Choisissez votre ambiance','Happy':'Heureux','Chill':'Détente','Energy':'Énergie','Love':'Amour','How to use':'Mode d’emploi','Search and play licensed music, watch YouTube in-app, or choose audio files stored on your phone.':'Recherchez de la musique sous licence, regardez YouTube dans l’app ou choisissez des fichiers du téléphone.','Music service is unavailable right now. Your internet may still be working—try again.':'Le service musical est indisponible. Votre connexion peut fonctionner ; réessayez.'},
      'zh': {'FEEL EVERY VIBE':'感受每一种节奏','Your sound. Your mood.':'你的音乐，你的心情。','Music that moves you':'让音乐打动你','Search songs or artists':'搜索歌曲或艺人','Licensed audio':'授权音乐','On-device songs':'手机本地歌曲','Choose songs':'选择歌曲','No songs selected':'尚未选择歌曲','Choose your vibe':'选择你的风格','Happy':'快乐','Chill':'放松','Energy':'活力','Love':'爱情','How to use':'使用方法','Search and play licensed music, watch YouTube in-app, or choose audio files stored on your phone.':'搜索授权音乐、在应用内观看 YouTube，或选择手机中保存的音频文件。','Music service is unavailable right now. Your internet may still be working—try again.':'音乐服务暂时不可用。网络可能正常，请稍后重试。'},
    };
    return translations[widget.settings.language]?[key] ?? key;
  }

  Future<void> _pickDeviceSongs() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.audio, allowMultiple: true);
    if (!mounted || picked == null) return;
    setState(() => _deviceSongs = picked.files.where((file) => file.path != null).toList());
  }

  Future<void> _searchMood(String mood) async {
    searchController.text = mood;
    await search();
  }

  Future<void> search() async {
    final query = searchController.text.trim();
    if (query.isEmpty) {
      _searchRequestId++;
      setState(() {
        loading = false;
        tracks = [];
        _hasSearched = false;
        error = 'Enter a song, artist or album name first.';
      });
      return;
    }

    final requestId = ++_searchRequestId;
    final source = _searchSource;
    setState(() {
      loading = true;
      error = null;
      tracks = [];
      _hasSearched = true;
    });

    try {
      final results = source == 'youtube'
          ? await youtubeApi.search(query)
          : await api.search(query);
      if (!mounted || requestId != _searchRequestId) return;
      setState(() {
        tracks = results;
        error = results.isEmpty ? 'No results found. Try another search.' : null;
      });
    } catch (_) {
      if (!mounted || requestId != _searchRequestId) return;
      setState(() {
        tracks = [];
        error = _tr('Music service is unavailable right now. Your internet may still be working—try again.');
      });
      await NotificationService.instance.showImportant(
        id: 2010,
        title: 'Music search failed',
        body: 'The music service did not respond. Your internet may still be working.',
        payload: 'retry_search',
      );
    } finally {
      if (mounted && requestId == _searchRequestId) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _download(MusicTrack track) async {
    if (_downloading.contains(track.id)) return;
    setState(() => _downloading.add(track.id));
    try {
      final url = await api.downloadUrl(track.id);
      await DownloadService.instance.download(track, url);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${track.title} saved for offline listening.')),
        );
      }
      await NotificationService.instance.notifyDownloadComplete(track.title);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: ${e.toString().replaceFirst('Exception: ', '')}')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading.remove(track.id));
    }
  }

  Future<void> play(MusicTrack track) async {
    try {
      if (track.source == 'youtube') {
        await player.pause();
        if (!mounted) return;
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => YoutubePlayerPage(track: track)));
        return;
      }
      setState(() => current = track);
      if (track.source == 'device') {
        final path = track.streamUrl;
        if (path == null || path.isEmpty) throw Exception('Audio file path is missing.');
        await player.setFilePath(path);
      } else {
        final url = await api.playUrl(track.id);
        await player.setUrl(url);
      }
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


  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(13)),
            child: Icon(Icons.graphic_eq_rounded, color: scheme.onPrimary, size: 25),
          ),
          const SizedBox(width: 10),
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('SokoVibe', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            Text('M U S I C', style: TextStyle(fontSize: 10, letterSpacing: 2.2, fontWeight: FontWeight.w700)),
          ]),
        ]),
        actions: [
          IconButton(
            tooltip: 'Account',
            onPressed: _showAccountOptions,
            icon: Icon(_accountEmail != null ? Icons.account_circle : Icons.login_rounded),
          ),
          IconButton(
            tooltip: 'Downloads',
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => DownloadsPage(
                  player: player,
                  onPlay: (downloaded) async {
                    setState(() => current = downloaded.toMusicTrack());
                    await player.setFilePath(downloaded.filePath);
                    await player.play();
                  },
                ),
              ));
              if (mounted) setState(() {});
            },
            icon: const Icon(Icons.download_for_offline_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: 'Language', icon: const Icon(Icons.translate_rounded),
            onSelected: (language) async { await widget.settings.saveLanguage(language); if (mounted) setState(() {}); },
            itemBuilder: (_) => const [PopupMenuItem(value: 'en', child: Text('English')), PopupMenuItem(value: 'zh', child: Text('中文')), PopupMenuItem(value: 'fr', child: Text('Français')), PopupMenuItem(value: 'sw', child: Text('Kiswahili'))],
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => AppSettingsPage(settings: widget.settings, onChanged: widget.onSettingsChanged),
              ));
              if (mounted) setState(() {});
            },
            icon: const Icon(Icons.tune_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_tr('FEEL EVERY VIBE'), style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.primary, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
              const SizedBox(height: 8),
              Text(_tr('Your sound. Your mood.'), style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800, letterSpacing: -1.1, height: 1.08)),
              const SizedBox(height: 5),
              Text(_tr('Music that moves you'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 18),
              SearchBar(
                controller: searchController,
                hintText: _tr('Search songs or artists'),
                leading: const Icon(Icons.search_rounded),
                trailing: [
                  if (loading) const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                  else IconButton(onPressed: search, tooltip: 'Search', icon: const Icon(Icons.arrow_forward_rounded)),
                ],
                onSubmitted: (_) => search(),
              ),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment<String>(value: 'licensed', label: Text(_tr('Licensed audio')), icon: Icon(Icons.headphones_rounded)),
                  ButtonSegment<String>(value: 'youtube', label: Text('YouTube'), icon: Icon(Icons.smart_display_rounded)),
                ],
                selected: {_searchSource},
                onSelectionChanged: (selection) {
                  _searchRequestId++;
                  setState(() { _searchSource = selection.first; tracks = []; error = null; loading = false; _hasSearched = false; });
                  if (searchController.text.trim().isNotEmpty) search();
                },
              ),
            ]),
          ),
          if (loading) const LinearProgressIndicator(minHeight: 2),
          if (error != null)
            Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 8), child: Material(
              color: scheme.errorContainer, borderRadius: BorderRadius.circular(16),
              child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
                Icon(Icons.wifi_off_rounded, color: scheme.onErrorContainer),
                const SizedBox(width: 10),
                Expanded(child: Text(error!, style: TextStyle(color: scheme.onErrorContainer))),
                IconButton(onPressed: search, tooltip: 'Try again', icon: Icon(Icons.refresh_rounded, color: scheme.onErrorContainer)),
              ])))),
          Expanded(
            child: tracks.isEmpty && _hasSearched
                ? loading
                    ? const Center(child: CircularProgressIndicator())
                    : Center(child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.search_off_rounded, size: 56, color: scheme.onSurfaceVariant),
                      const SizedBox(height: 12),
                      Text('No results found', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 6),
                      const Text('Try a different song, artist or search source.', textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(onPressed: search, icon: const Icon(Icons.refresh_rounded), label: const Text('Search again')),
                    ]),
                  ))
                : tracks.isEmpty
                ? ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    children: [
                      Container(
                        margin: const EdgeInsets.only(bottom: 18), padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(22), border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5))),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [Icon(Icons.phone_android_rounded, color: scheme.primary, size: 25), const SizedBox(width: 9), Expanded(child: Text(_tr('On-device songs'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))), FilledButton.tonalIcon(onPressed: _pickDeviceSongs, icon: const Icon(Icons.library_music_rounded), label: Text(_tr('Choose songs')))]),
                          const SizedBox(height: 6),
                          if (_deviceSongs.isEmpty) Text(_tr('No songs selected'), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant))
                          else ..._deviceSongs.map((file) => ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.music_note_rounded), title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis), trailing: IconButton(tooltip: 'Play', icon: Icon(Icons.play_circle_fill_rounded, color: scheme.primary, size: 30), onPressed: () => play(MusicTrack(id: file.path ?? file.name, title: file.name.replaceFirst(RegExp(r'\.[^.]+$'), ''), artist: 'On this device', image: '', streamUrl: file.path, source: 'device'))))),
                        ]),
                      ),
                      Text(_tr('Choose your vibe'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 12),
                      GridView.count(
                        crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.55,
                        children: [
                          _MoodCard(title: _tr('Happy'), subtitle: 'Feel-good music', icon: Icons.wb_sunny_rounded, color: const Color(0xFFB8F36B), onTap: () => _searchMood('happy afrobeat')),
                          _MoodCard(title: _tr('Chill'), subtitle: 'Relaxing sounds', icon: Icons.nightlight_round, color: const Color(0xFF9CC8FF), onTap: () => _searchMood('chill acoustic')),
                          _MoodCard(title: _tr('Energy'), subtitle: 'High energy', icon: Icons.bolt_rounded, color: const Color(0xFFFFC36B), onTap: () => _searchMood('energetic dance')),
                          _MoodCard(title: _tr('Love'), subtitle: 'Romantic songs', icon: Icons.favorite_rounded, color: const Color(0xFFFF9CCB), onTap: () => _searchMood('love romantic')),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                            colors: [scheme.primaryContainer, scheme.surfaceContainerHighest]),
                        ),
                        child: Row(children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Find your next favourite', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 5),
                            Text('Discover something new.', style: Theme.of(context).textTheme.bodySmall),
                            const SizedBox(height: 12),
                            FilledButton.icon(onPressed: () { searchController.text = 'afrobeat'; search(); },
                              icon: const Icon(Icons.explore_rounded), label: const Text('Explore')),
                          ])),
                          Icon(Icons.graphic_eq_rounded, size: 64, color: scheme.primary),
                        ]),
                      ),
                      const SizedBox(height: 14),
                      Card(child: ListTile(leading: Icon(Icons.lightbulb_outline_rounded, color: scheme.primary), title: Text(_tr('How to use'), style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(_tr('Search and play licensed music, watch YouTube in-app, or choose audio files stored on your phone.')))),
                      const SizedBox(height: 14),
                      Text(_tr('Discover music'), style: Theme.of(context).textTheme.titleSmall?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                    itemCount: tracks.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final track = tracks[i];
                      return Card(
                        color: scheme.surfaceContainerLow,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(13),
                            child: CachedNetworkImage(imageUrl: track.image, width: 58, height: 58, fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Container(width: 58, height: 58, color: scheme.surfaceContainerHighest, child: const Icon(Icons.music_note_rounded))),
                          ),
                          title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: Wrap(spacing: 0, children: [
                            IconButton(
                              tooltip: track.downloadAllowed
                                  ? 'Download for offline'
                                  : 'Download unavailable for this license',
                              onPressed: (!track.downloadAllowed || _downloading.contains(track.id)) ? null : () => _download(track),
                              icon: _downloading.contains(track.id)
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.download_rounded),
                            ),
                            IconButton(tooltip: 'Lyrics', onPressed: () => showLyrics(track), icon: const Icon(Icons.lyrics_outlined)),
                            IconButton(tooltip: 'Play', onPressed: () => play(track), icon: Icon(Icons.play_circle_fill_rounded, color: scheme.primary, size: 32)),
                          ]),
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

class _MoodCard extends StatelessWidget {
  const _MoodCard({required this.title, required this.subtitle, required this.icon, required this.color, required this.onTap});
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: dark ? Theme.of(context).colorScheme.surfaceContainerLow : color.withValues(alpha: 0.28),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Container(width: 38, height: 38, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(13)),
              child: Icon(icon, color: const Color(0xFF152016))),
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ])),
              Icon(Icons.arrow_outward_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
            ]),
          ]),
        ),
      ),
    );
  }
}

class YoutubePlayerPage extends StatefulWidget {
  const YoutubePlayerPage({super.key, required this.track});
  final MusicTrack track;
  @override State<YoutubePlayerPage> createState() => _YoutubePlayerPageState();
}
class _YoutubePlayerPageState extends State<YoutubePlayerPage> {
  late final WebViewController _controller;
  @override void initState() {
    super.initState();
    _controller = WebViewController()..setJavaScriptMode(JavaScriptMode.unrestricted)..setBackgroundColor(const Color(0xFF080D0B))..loadHtmlString('''
<!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1"><style>html,body{margin:0;width:100%;height:100%;background:#080D0B}.player{position:absolute;inset:0;display:flex;align-items:center;justify-content:center}iframe{width:100%;height:100%;border:0}</style></head>
<body><div class="player"><iframe src="https://www.youtube.com/embed/${widget.track.id}?autoplay=1&playsinline=1&controls=1&rel=0" title="YouTube player" allow="autoplay; encrypted-media; picture-in-picture; fullscreen" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe></div></body></html>
''', baseUrl: 'https://www.youtube.com');
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('YouTube'), actions: [IconButton(tooltip: 'Reload', onPressed: () => _controller.reload(), icon: const Icon(Icons.refresh_rounded))]), body: Column(children: [Expanded(child: WebViewWidget(controller: _controller)), ListTile(leading: const Icon(Icons.smart_display_rounded), title: Text(widget.track.title, maxLines: 2, overflow: TextOverflow.ellipsis), subtitle: Text(widget.track.artist)), const SafeArea(top: false, child: Padding(padding: EdgeInsets.all(12), child: Text('Playback is provided by YouTube. Some videos may block embedded playback.', textAlign: TextAlign.center)))]));
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
          Text('Language', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: DropdownButtonFormField<String>(
            value: settings.language, decoration: const InputDecoration(border: InputBorder.none, prefixIcon: Icon(Icons.translate_rounded)),
            items: const [DropdownMenuItem(value: 'en', child: Text('English')), DropdownMenuItem(value: 'zh', child: Text('中文')), DropdownMenuItem(value: 'fr', child: Text('Français')), DropdownMenuItem(value: 'sw', child: Text('Kiswahili'))],
            onChanged: (value) async { if (value == null) return; await settings.saveLanguage(value); if (mounted) setState(() {}); widget.onChanged(); },
          ))),
          const SizedBox(height: 20),
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
          Text('Sound identity', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(child: SwitchListTile(
            secondary: const Icon(Icons.graphic_eq_rounded),
            title: const Text('Startup signature sound'),
            subtitle: const Text('Play the short futuristic SokoVibe sound once when the app starts.'),
            value: settings.startupSound,
            onChanged: (enabled) async {
              await settings.saveStartupSound(enabled);
              if (mounted) setState(() {});
            },
          )),
          const SizedBox(height: 20),
          Text('Notifications', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(children: [
              SwitchListTile(
                secondary: const Icon(Icons.notifications_active_outlined),
                title: const Text('Daily listening reminder'),
                subtitle: const Text('A daily reminder to listen to music.'),
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
              subtitle: const Text('0.1.0'),
              onTap: () => showAboutDialog(
                context: context,
                applicationName: 'Soko Vibe Music',
                applicationVersion: '0.1.0',
                applicationLegalese: 'Made for music discovery.',
              ),
            ),
          ])),
          const SizedBox(height: 12),
          Text(
            'Settings are saved on this device. Music search and lyrics need an internet connection; downloaded/offline features depend on the relevant feature being implemented.',
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


class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key, required this.player, required this.onPlay});
  final AudioPlayer player;
  final Future<void> Function(DownloadedTrack track) onPlay;

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  List<DownloadedTrack> items = <DownloadedTrack>[];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final saved = await DownloadService.instance.list();
      if (mounted) setState(() => items = saved);
    } catch (_) {
      if (mounted) setState(() => error = 'Could not load downloaded music.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _delete(DownloadedTrack item) async {
    try {
      await DownloadService.instance.delete(item);
      if (mounted) {
        setState(() => items.removeWhere((saved) => saved.id == item.id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Removed ${item.title} from downloads.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete this download.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        actions: [
          IconButton(
            tooltip: 'Refresh downloads',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(error!),
                      const SizedBox(height: 8),
                      FilledButton(onPressed: _refresh, child: const Text('Retry')),
                    ],
                  ),
                )
              : items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.download_for_offline_outlined, size: 64, color: scheme.primary),
                            const SizedBox(height: 12),
                            Text('No offline music yet', style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 6),
                            const Text('Use the download icon on a song while online. Your saved tracks will appear here.'),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return Card(
                          color: scheme.surfaceContainerLow,
                          child: ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: CachedNetworkImage(
                                imageUrl: item.image,
                                width: 52,
                                height: 52,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Container(
                                  width: 52,
                                  height: 52,
                                  color: scheme.surfaceContainerHighest,
                                  child: const Icon(Icons.music_note_rounded),
                                ),
                              ),
                            ),
                            title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text('${item.artist} · Offline ready'),
                            trailing: Wrap(
                              spacing: 0,
                              children: [
                                IconButton(
                                  tooltip: 'Play offline',
                                  onPressed: () async {
                                    try {
                                      await widget.onPlay(item);
                                    } catch (_) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('This saved file could not be played. Try downloading it again.')),
                                      );
                                    }
                                  },
                                  icon: Icon(Icons.play_circle_fill_rounded, color: scheme.primary, size: 30),
                                ),
                                IconButton(
                                  tooltip: 'Delete download',
                                  onPressed: () => _delete(item),
                                  icon: const Icon(Icons.delete_outline_rounded),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
