import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/on_device_music_service.dart';
import 'music_account_screen.dart';

const _api = 'https://sokovibe-music-api.onrender.com';

class MusicCatalogScreen extends StatefulWidget {
  const MusicCatalogScreen({super.key});
  @override
  State<MusicCatalogScreen> createState() => _MusicCatalogScreenState();
}

class _MusicCatalogScreenState extends State<MusicCatalogScreen> with SingleTickerProviderStateMixin {
  final _search = TextEditingController();
  final _player = AudioPlayer();
  final _device = OnDeviceMusicService();
  late final TabController _tabs;
  List<Map<String, dynamic>> _songs = [], _online = [];
  Set<String> _favorites = {};
  bool _scanBusy = false, _searchBusy = false, _playing = false, _favoritesOnly = false;
  String? _localError, _onlineError, _playingId, _playingTitle, _playingArtist;
  String _kind = 'music';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this)..addListener(() { if (mounted) setState(() {}); });
    _player.playerStateStream.listen((s) { if (mounted) setState(() => _playing = s.playing); });
    _loadFavorites();
    _start();
  }

  @override
  void dispose() { _tabs.dispose(); _search.dispose(); _player.dispose(); super.dispose(); }

  Future<void> _start() async {
    final seen = await _device.hasSeenOnboarding();
    if (!mounted) return;
    if (!seen) {
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _welcome(); });
    } else if (await _device.hasPermission) {
      await _scan();
    }
  }

  Future<void> _welcome() async {
    await showDialog<void>(context: context, barrierDismissible: false, builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.graphic_eq_rounded, size: 48),
      title: const Text('Karibu SokoVibe Music'),
      content: const Text('Sikiliza nyimbo zilizohifadhiwa kwenye simu yako na ugundue muziki mtandaoni. Ruhusu ufikiaji wa audio ili nyimbo zako zionekane moja kwa moja. Hatutafuta wala kubadilisha faili zako.'),
      actions: [
        TextButton(onPressed: () async { await _device.markOnboardingSeen(); if (ctx.mounted) Navigator.pop(ctx); }, child: const Text('Baadaye')),
        FilledButton.icon(onPressed: () async { await _device.markOnboardingSeen(); if (ctx.mounted) Navigator.pop(ctx); await _requestAndScan(); }, icon: const Icon(Icons.library_music), label: const Text('Endelea')),
      ],
    ));
  }

  Future<void> _requestAndScan() async {
    try {
      final ok = await _device.requestPermissionOnce();
      if (!ok) {
        if (mounted) setState(() => _localError = 'Ruhusa haijatolewa. Washa Music and audio kwenye App settings kisha jaribu tena.');
        return;
      }
      await _scan();
    } on PlatformException catch (e) {
      if (mounted) setState(() => _localError = e.message ?? 'Ruhusa ya audio inahitajika.');
    } catch (e) { if (mounted) setState(() => _localError = 'Imeshindikana kuomba ruhusa: $e'); }
  }

  Future<void> _scan() async {
    if (_scanBusy) return;
    setState(() { _scanBusy = true; _localError = null; });
    try {
      final found = await _device.scan();
      if (mounted) setState(() => _songs = found);
    } on PlatformException catch (e) {
      if (mounted) setState(() => _localError = e.message ?? 'Scan imeshindikana.');
    } catch (e) { if (mounted) setState(() => _localError = 'Scan imeshindikana: $e'); }
    finally { if (mounted) setState(() => _scanBusy = false); }
  }

  Future<void> _loadFavorites() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) setState(() => _favorites = (p.getStringList('sokovibe_music_favorites_v1') ?? []).toSet());
  }

  Future<void> _favorite(String id) async {
    final next = Set<String>.from(_favorites);
    if (!next.add(id)) next.remove(id);
    final p = await SharedPreferences.getInstance();
    await p.setStringList('sokovibe_music_favorites_v1', next.toList());
    if (mounted) setState(() => _favorites = next);
  }

  List<Map<String, dynamic>> get _visibleSongs {
    final q = _search.text.trim().toLowerCase();
    return _songs.where((s) {
      if (_favoritesOnly && !_favorites.contains('local:${s['id']}')) return false;
      if (q.isEmpty) return true;
      return '${s['title']} ${s['artist']} ${s['album']} ${s['relativePath']}'.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _playLocal(Map<String, dynamic> song) async {
    final uri = song['contentUri']?.toString() ?? '';
    if (!uri.startsWith('content://')) { _toast('URI ya wimbo haipatikani.'); return; }
    final id = 'local:${song['id']}';
    try {
      if (_playingId == id && _playing) { await _player.pause(); return; }
      if (_playingId == id && !_playing) { await _player.play(); return; }
      await _player.setUrl(uri);
      if (!mounted) return;
      setState(() { _playingId = id; _playingTitle = song['title']?.toString(); _playingArtist = song['artist']?.toString(); });
      await _player.play();
    } catch (e) { _toast('Imeshindikana kucheza faili hili: $e'); }
  }

  Future<void> _searchOnline() async {
    final q = _search.text.trim();
    if (q.isEmpty) { setState(() { _online = []; _onlineError = null; }); return; }
    setState(() { _searchBusy = true; _onlineError = null; });
    try {
      final uri = Uri.parse('$_api/api/v1/catalog/search').replace(queryParameters: {'q': q, 'kind': _kind});
      final res = await http.get(uri).timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final items = (body['results'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      if (mounted) setState(() { _online = items; if (items.isEmpty) _onlineError = 'Hakuna matokeo yenye leseni wazi yaliyopatikana.'; });
    } catch (e) { if (mounted) setState(() => _onlineError = 'Huduma ya mtandaoni haipatikani sasa.'); }
    finally { if (mounted) setState(() => _searchBusy = false); }
  }

  Future<void> _playOnline(Map<String, dynamic> item) async {
    try {
      String? url = item['streamUrl']?.toString();
      final path = item['streamLookupUrl']?.toString();
      if ((url == null || !url.startsWith('https://')) && path != null && path.startsWith('/api/v1/catalog/play/')) {
        final res = await http.get(Uri.parse('$_api$path')).timeout(const Duration(seconds: 20));
        if (res.statusCode == 200) url = (jsonDecode(res.body) as Map<String, dynamic>)['streamUrl']?.toString();
      }
      if (url == null || !url.startsWith('https://')) throw Exception('Hakuna stream iliyoidhinishwa.');
      await _player.setUrl(url);
      if (!mounted) return;
      setState(() { _playingId = 'online:${item['provider']}:${item['id']}'; _playingTitle = item['title']?.toString(); _playingArtist = item['creator']?.toString(); });
      await _player.play();
    } catch (e) { _toast('Playback imeshindikana: $e'); }
  }

  void _toast(String text) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text))); }
  String _duration(dynamic value) { final s = ((value as num?)?.toInt() ?? 0) ~/ 1000; return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}'; }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('SokoVibe Music', style: TextStyle(fontWeight: FontWeight.w800)),
          Text('YOUR SOUND. YOUR VIBE.', style: TextStyle(fontSize: 10, letterSpacing: 1.6)),
        ]),
        actions: [IconButton(tooltip: 'Akaunti na mipangilio', onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const MusicAccountScreen())), icon: const Icon(Icons.account_circle_outlined))],
        bottom: TabBar(controller: _tabs, tabs: const [Tab(text: 'ON DEVICE', icon: Icon(Icons.phone_android_rounded)), Tab(text: 'EXPLORE ONLINE', icon: Icon(Icons.language_rounded))]),
      ),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 8), child: TextField(
          controller: _search, onChanged: (_) => setState(() {}),
          onSubmitted: (_) { if (_tabs.index == 1) _searchOnline(); },
          decoration: InputDecoration(
            hintText: _tabs.index == 0 ? 'Search songs, artists, albums' : 'Discover songs and artists',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: IconButton(onPressed: _tabs.index == 0 ? () => setState(() {}) : _searchOnline, icon: const Icon(Icons.arrow_forward_rounded)),
            filled: true, fillColor: c.surfaceContainerHighest.withValues(alpha: .55),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(26), borderSide: BorderSide.none),
          ),
        )),
        Expanded(child: TabBarView(controller: _tabs, children: [_localTab(c), _onlineTab(c)])),
        if (_playingId != null) SafeArea(top: false, child: Container(
          margin: const EdgeInsets.fromLTRB(10, 4, 10, 8), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: c.inverseSurface, borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            Icon(Icons.graphic_eq_rounded, color: c.onInverseSurface), const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(_playingTitle ?? 'SokoVibe Music', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.onInverseSurface, fontWeight: FontWeight.w700)),
              Text(_playingArtist ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.onInverseSurface.withValues(alpha: .7), fontSize: 12)),
            ])),
            IconButton(onPressed: () => _playing ? _player.pause() : _player.play(), icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: c.onInverseSurface)),
            IconButton(onPressed: () async { await _player.stop(); if (mounted) setState(() => _playingId = null); }, icon: Icon(Icons.close_rounded, color: c.onInverseSurface)),
          ]),
        )),
      ]),
    );
  }

  Widget _localTab(ColorScheme c) {
    final list = _visibleSongs;
    return RefreshIndicator(onRefresh: _scan, child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 20), children: [
      Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c.primaryContainer, c.surfaceContainerHighest]),
      ), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.graphic_eq_rounded, size: 30, color: c.onPrimaryContainer),
        const SizedBox(height: 10),
        Text('Your music, all in one place', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c.onSurface)),
        const SizedBox(height: 6),
        Text(_songs.isEmpty ? 'Scan your phone and your songs will appear here.' : '${_songs.length} songs found on this device', style: TextStyle(color: c.onSurfaceVariant)),
        const SizedBox(height: 14),
        Wrap(spacing: 8, children: [
          FilledButton.icon(onPressed: _scanBusy ? null : (_songs.isEmpty ? _requestAndScan : _scan), icon: Icon(_scanBusy ? Icons.hourglass_top : Icons.sync), label: Text(_scanBusy ? 'Scanning…' : (_songs.isEmpty ? 'Find my music' : 'Rescan'))),
          OutlinedButton.icon(onPressed: () => setState(() => _favoritesOnly = !_favoritesOnly), icon: Icon(_favoritesOnly ? Icons.favorite : Icons.favorite_border), label: Text(_favoritesOnly ? 'All songs' : 'Favorites')),
        ]),
      ])),
      if (_localError != null) Padding(padding: const EdgeInsets.only(top: 10), child: Card(child: ListTile(
        leading: const Icon(Icons.info_outline), title: Text(_localError!),
        trailing: IconButton(onPressed: openAppSettings, icon: const Icon(Icons.settings_outlined)),
      ))),
      const SizedBox(height: 16),
      Row(children: [const Expanded(child: Text('On Device Songs', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))), Text('${list.length} songs', style: TextStyle(color: c.onSurfaceVariant))]),
      if (_scanBusy) const Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator()))
      else if (list.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 28), child: Column(children: [
        Icon(Icons.library_music_outlined, size: 50, color: c.onSurfaceVariant), const SizedBox(height: 10),
        Text(_localError == null ? 'No music found yet' : 'Music access needed', style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 5),
        Text('Music files on your phone appear here after permission is granted.', textAlign: TextAlign.center, style: TextStyle(color: c.onSurfaceVariant)),
      ]))
      else ...list.map((s) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        leading: Container(width: 52, height: 52, decoration: BoxDecoration(color: c.primaryContainer, borderRadius: BorderRadius.circular(12)), child: Icon(_playingId == 'local:${s['id']}' && _playing ? Icons.equalizer : Icons.music_note, color: c.onPrimaryContainer)),
        title: Text(s['title']?.toString() ?? 'Unknown title', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${s['artist'] ?? 'Unknown artist'} • ${_duration(s['duration'])}\n${s['relativePath'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: PopupMenuButton<String>(
          onSelected: (v) { if (v == 'play') _playLocal(s); if (v == 'fav') _favorite('local:${s['id']}'); if (v == 'info') showDialog<void>(context: context, builder: (_) => AlertDialog(
            title: Text(s['title']?.toString() ?? 'Track details'),
            content: Text('Artist: ${s['artist']}\nAlbum: ${s['album']}\nFormat: ${s['mimeType']}\nSize: ${(((s['size'] as num?)?.toDouble() ?? 0) / 1048576).toStringAsFixed(1)} MB\nLocation: ${s['filePath'] ?? s['relativePath']}'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
          )); },
          itemBuilder: (_) => [const PopupMenuItem(value: 'play', child: Text('Play')), PopupMenuItem(value: 'fav', child: Text(_favorites.contains('local:${s['id']}') ? 'Remove favorite' : 'Add to favorites')), const PopupMenuItem(value: 'info', child: Text('Track details'))],
        ),
        onTap: () => _playLocal(s),
      )),
    ]));
  }

  Widget _onlineTab(ColorScheme c) {
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Row(children: [
        const Text('Discover music', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)), const Spacer(),
        SegmentedButton<String>(segments: const [ButtonSegment(value: 'music', label: Text('Music')), ButtonSegment(value: 'movie', label: Text('Video'))], selected: {_kind}, onSelectionChanged: (v) { setState(() => _kind = v.first); if (_search.text.trim().isNotEmpty) _searchOnline(); }),
      ])),
      if (_searchBusy) const LinearProgressIndicator(minHeight: 2),
      Expanded(child: _online.isEmpty ? Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.public_rounded, size: 50, color: c.primary), const SizedBox(height: 12),
        Text(_onlineError ?? 'Search authorized music online', textAlign: TextAlign.center),
        const SizedBox(height: 6), const Text('Results depend on provider availability and licensing.', textAlign: TextAlign.center),
        if (_onlineError != null) TextButton(onPressed: _searchOnline, child: const Text('Try again')),
      ]))) : ListView.separated(padding: const EdgeInsets.all(12), itemCount: _online.length, separatorBuilder: (_, __) => const SizedBox(height: 4), itemBuilder: (_, i) {
        final s = _online[i]; final image = s['image']?.toString(); final id = 'online:${s['provider']}:${s['id']}';
        return ListTile(
          leading: ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: 54, height: 54, child: image != null && image.startsWith('https://') ? Image.network(image, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _onlineCover(c)) : _onlineCover(c))),
          title: Text(s['title']?.toString() ?? 'Untitled', maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text('${s['creator'] ?? 'Artist not listed'} • ${s['provider'] ?? 'Provider'}\n${s['license'] ?? 'License not listed'}', maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: IconButton.filledTonal(onPressed: () => _playOnline(s), icon: Icon(_playingId == id && _playing ? Icons.pause : Icons.play_arrow)),
          onTap: () { final u = Uri.tryParse(s['sourceUrl']?.toString() ?? ''); if (u?.scheme == 'https') launchUrl(u!, mode: LaunchMode.externalApplication); },
        );
      })),
    ]);
  }

  Widget _onlineCover(ColorScheme c) => Container(color: c.primaryContainer, alignment: Alignment.center, child: Icon(Icons.album, color: c.onPrimaryContainer));
}
