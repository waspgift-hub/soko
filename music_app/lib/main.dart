import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'models/music_track.dart';
import 'services/music_api.dart';
import 'services/notification_service.dart';
import 'services/lyrics_service.dart';
import 'services/app_settings.dart';
import 'services/auth_service.dart';
import 'services/sound_identity.dart';

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
  final player = AudioPlayer();
  final searchController = TextEditingController();
  List<MusicTrack> tracks = [];
  MusicTrack? current;
  bool loading = false;
  String? error;
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
              Navigator.pop(dialogContext);
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
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Google sign-in successful.')),
                );
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
    player.dispose();
    super.dispose();
  }

  Future<void> _searchMood(String mood) async {
    searchController.text = mood;
    await search();
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
            tooltip: 'Account / Akaunti',
            onPressed: _showAccountOptions,
            icon: Icon(_accountEmail != null ? Icons.account_circle : Icons.login_rounded),
          ),
          IconButton(
            tooltip: 'Settings / Mipangilio',
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
              Text('FEEL EVERY VIBE  ·  HISI KILA HISIA', style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.primary, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
              const SizedBox(height: 8),
              Text('Your sound. Your mood.', style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800, letterSpacing: -1.1, height: 1.08)),
              const SizedBox(height: 5),
              Text('Muziki unaoendana na wewe · Music that moves you',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 18),
              SearchBar(
                controller: searchController,
                hintText: 'Tafuta nyimbo / Search songs or artists',
                leading: const Icon(Icons.search_rounded),
                trailing: [
                  if (loading) const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                  else IconButton(onPressed: search, tooltip: 'Search / Tafuta', icon: const Icon(Icons.arrow_forward_rounded)),
                ],
                onSubmitted: (_) => search(),
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
                IconButton(onPressed: search, tooltip: 'Try again / Jaribu tena', icon: Icon(Icons.refresh_rounded, color: scheme.onErrorContainer)),
              ]))),
          Expanded(
            child: tracks.isEmpty
                ? ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    children: [
                      Text('Choose your vibe  ·  Chagua mood yako', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 12),
                      GridView.count(
                        crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.55,
                        children: [
                          _MoodCard(title: 'Happy', subtitle: 'Furaha', icon: Icons.wb_sunny_rounded, color: const Color(0xFFB8F36B), onTap: () => _searchMood('happy afrobeat')),
                          _MoodCard(title: 'Chill', subtitle: 'Pumzika', icon: Icons.nightlight_round, color: const Color(0xFF9CC8FF), onTap: () => _searchMood('chill acoustic')),
                          _MoodCard(title: 'Energy', subtitle: 'Nguvu', icon: Icons.bolt_rounded, color: const Color(0xFFFFC36B), onTap: () => _searchMood('energetic dance')),
                          _MoodCard(title: 'Love', subtitle: 'Mapenzi', icon: Icons.favorite_rounded, color: const Color(0xFFFF9CCB), onTap: () => _searchMood('love romantic')),
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
                            Text('Tafuta wimbo mpya wa kupenda.', style: Theme.of(context).textTheme.bodySmall),
                            const SizedBox(height: 12),
                            FilledButton.icon(onPressed: () { searchController.text = 'afrobeat'; search(); },
                              icon: const Icon(Icons.explore_rounded), label: const Text('Explore / Gundua')),
                          ])),
                          Icon(Icons.graphic_eq_rounded, size: 64, color: scheme.primary),
                        ]),
                      ),
                      const SizedBox(height: 14),
                      Text('Discover music · Gundua muziki', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: scheme.onSurfaceVariant)),
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
                            IconButton(tooltip: 'Lyrics / Maneno', onPressed: () => showLyrics(track), icon: const Icon(Icons.lyrics_outlined)),
                            IconButton(tooltip: 'Play / Cheza', onPressed: () => play(track), icon: Icon(Icons.play_circle_fill_rounded, color: scheme.primary, size: 32)),
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
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Allow notifications in Android settings to enable reminders.')),
        );
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
          Text('Appearance · Muonekano', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Theme · Mandhari'),
                const SizedBox(height: 8),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.settings_suggest_outlined), label: Text('System · Mfumo')),
                    ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Light · Mwanga')),
                    ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Dark · Giza')),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (selection) => _chooseTheme(selection.first),
                ),
                const SizedBox(height: 20),
                const Text('Accent colour · Rangi kuu'),
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
          Text('Sound identity · Sauti ya SokoVibe', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(child: SwitchListTile(
            secondary: const Icon(Icons.graphic_eq_rounded),
            title: const Text('Startup signature sound · Sauti ya mwanzo'),
            subtitle: const Text('Play the short futuristic SokoVibe sound once when the app starts.'),
            value: settings.startupSound,
            onChanged: (enabled) async {
              await settings.saveStartupSound(enabled);
              if (mounted) setState(() {});
            },
          )),
          const SizedBox(height: 20),
          Text('Notifications · Arifa', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(children: [
              SwitchListTile(
                secondary: const Icon(Icons.notifications_active_outlined),
                title: const Text('Daily listening reminder · Kikumbusho cha kila siku'),
                subtitle: const Text('Kumbusho la kusikiliza muziki kila siku'),
                value: settings.dailyReminder,
                onChanged: _changeReminder,
              ),
              const Divider(height: 1),
              ListTile(
                enabled: settings.dailyReminder,
                leading: const Icon(Icons.schedule),
                title: const Text('Reminder time · Muda wa kumbusho'),
                subtitle: Text(_timeLabel(context)),
                trailing: const Icon(Icons.chevron_right),
                onTap: settings.dailyReminder ? _chooseReminderTime : null,
              ),
            ]),
          ),
          const SizedBox(height: 20),
          Text('About · Kuhusu app', style: Theme.of(context).textTheme.titleMedium),
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
              title: const Text('App version · Toleo la app'),
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
