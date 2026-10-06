import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const OfflineUssdApp());

class OfflineUssdApp extends StatelessWidget {
  const OfflineUssdApp({super.key});

  @override
  Widget build(BuildContext context) {
    final light = ColorScheme.fromSeed(seedColor: const Color(0xFF0B7A4B));
    final dark = ColorScheme.fromSeed(seedColor: const Color(0xFF54D39A), brightness: Brightness.dark);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Soko Langu Offline USSD',
      theme: ThemeData(useMaterial3: true, colorScheme: light, inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder())),
      darkTheme: ThemeData(useMaterial3: true, colorScheme: dark, inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder())),
      themeMode: ThemeMode.system,
      home: const PairPage(),
    );
  }
}

class PairPage extends StatefulWidget {
  const PairPage({super.key});
  @override State<PairPage> createState() => _PairPageState();
}

class _PairPageState extends State<PairPage> {
  final url = TextEditingController();
  final token = TextEditingController();
  String status = 'PC na simu ziwe kwenye Wi‑Fi/router moja.';
  bool busy = false;

  @override
  void dispose() { url.dispose(); token.dispose(); super.dispose(); }

  Future<void> pair() async {
    final rawUrl = url.text.trim();
    final rawToken = token.text.trim();
    if (rawUrl.isEmpty || rawToken.isEmpty) {
      setState(() => status = 'Jaza PC URL na pairing token.');
      return;
    }
    setState(() { busy = true; status = 'Inaunganisha na PC…'; });
    try {
      var base = rawUrl;
      if (!base.startsWith('http://') && !base.startsWith('https://')) base = 'http://$base';
      base = base.replaceFirst(RegExp(r'/+$'), '');
      final res = await http.post(Uri.parse('$base/pair'), headers: {'Content-Type': 'application/json', 'X-Pair-Token': rawToken}, body: '{}').timeout(const Duration(seconds: 8));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 200 || data['sessionId'] == null) throw Exception(data['error'] ?? 'Pairing failed');
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => UssdPage(base: base, token: rawToken, sessionId: data['sessionId'].toString())));
    } catch (e) {
      setState(() => status = 'Imeshindikana: hakikisha URL, token na Wi‑Fi ni sahihi.');
    } finally { if (mounted) setState(() => busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(children: [
                Container(width: 88, height: 88, decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(28)), child: Icon(Icons.wifi_tethering_rounded, size: 46, color: cs.onPrimaryContainer)),
                const SizedBox(height: 22),
                Text('Soko Langu', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Offline USSD', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: cs.primary)),
                const SizedBox(height: 10),
                Text('Huduma ya ndani ya LAN — internet haihitajiki.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 28),
                Card(elevation: 0, color: cs.surfaceContainerHighest, child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Icon(Icons.router_rounded, color: cs.primary), const SizedBox(width: 10), Text('Unganisha PC', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))]),
                  const SizedBox(height: 16),
                  TextField(controller: url, keyboardType: TextInputType.url, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'PC URL', hintText: 'http://192.168.1.10:8787', prefixIcon: Icon(Icons.link_rounded))),
                  const SizedBox(height: 14),
                  TextField(controller: token, obscureText: true, decoration: const InputDecoration(labelText: 'Pairing token', prefixIcon: Icon(Icons.key_rounded))),
                  const SizedBox(height: 16),
                  SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: busy ? null : pair, icon: const Icon(Icons.login_rounded), label: Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(busy ? 'Inaunganisha…' : 'CONNECT')))),
                ]))),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.lock_outline_rounded, size: 17, color: cs.primary), const SizedBox(width: 7), Flexible(child: Text(status, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)))]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class UssdPage extends StatefulWidget {
  final String base, token, sessionId;
  const UssdPage({super.key, required this.base, required this.token, required this.sessionId});
  @override State<UssdPage> createState() => _UssdPageState();
}

class _UssdPageState extends State<UssdPage> {
  String title = 'SOKO LANGU';
  String text = 'Bonyeza SEND kuanza huduma.';
  List<String> options = const [];
  String input = '';
  bool busy = false;
  Timer? poller;

  @override
  void initState() {
    super.initState();
    poller = Timer.periodic(const Duration(seconds: 2), (_) => pollEvents());
    send('*123#');
  }

  @override
  void dispose() { poller?.cancel(); super.dispose(); }

  Future<void> send(String code) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final res = await http.post(Uri.parse('${widget.base}/ussd'), headers: {'Content-Type': 'application/json', 'X-Pair-Token': widget.token}, body: jsonEncode({'sessionId': widget.sessionId, 'code': code})).timeout(const Duration(seconds: 8));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 200) throw Exception(data['error'] ?? 'USSD error');
      setState(() { title = '${data['title'] ?? 'SOKO LANGU'}'; text = '${data['text'] ?? ''}'; options = ((data['options'] as List?) ?? const []).map((e) => '$e').toList(); input = ''; });
    } catch (_) {
      if (mounted) setState(() => text = 'PC haipatikani. Kagua Wi‑Fi na URL.');
    } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> pollEvents() async {
    try {
      final res = await http.get(Uri.parse('${widget.base}/events?sessionId=${Uri.encodeComponent(widget.sessionId)}'), headers: {'X-Pair-Token': widget.token}).timeout(const Duration(seconds: 3));
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final events = (data['events'] as List?) ?? const [];
      if (events.isNotEmpty && mounted) {
        final e = events.last as Map<String, dynamic>;
        setState(() { title = '${e['title'] ?? 'SOKO LANGU'}'; text = '${e['text'] ?? ''}'; });
      }
    } catch (_) {}
  }

  void add(String value) { if (!busy && input.length < 20) setState(() => input += value); }

  Widget key(String value) => Expanded(child: Padding(padding: const EdgeInsets.all(5), child: FilledButton.tonal(onPressed: () => add(value), style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))), child: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)))));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('USSD Session'), actions: [IconButton(tooltip: 'Mwanzo', onPressed: busy ? null : () => send('*123#'), icon: const Icon(Icons.home_rounded))]),
      body: SafeArea(child: Column(children: [
        Expanded(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Column(children: [
          Card(elevation: 0, color: cs.primaryContainer, child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(Icons.phone_in_talk_rounded, color: cs.onPrimaryContainer), const SizedBox(width: 10), Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: cs.onPrimaryContainer)))]),
            const SizedBox(height: 16),
            SelectableText(text, style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.45, color: cs.onPrimaryContainer)),
            if (options.isNotEmpty) ...[const SizedBox(height: 14), Wrap(spacing: 8, runSpacing: 8, children: options.map((o) => Chip(label: Text(o))).toList())],
            const SizedBox(height: 14),
            Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), decoration: BoxDecoration(color: cs.surface.withOpacity(.65), borderRadius: BorderRadius.circular(14)), child: Text(input.isEmpty ? 'Ingiza chaguo…' : input, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
          ])),
        ]))),
        Container(color: cs.surface, padding: const EdgeInsets.fromLTRB(10, 6, 10, 12), child: Column(children: [
          Row(children: [key('1'), key('2'), key('3')]),
          Row(children: [key('4'), key('5'), key('6')]),
          Row(children: [key('7'), key('8'), key('9')]),
          Row(children: [key('*'), key('0'), key('#')]),
          Row(children: [Expanded(child: OutlinedButton.icon(onPressed: busy ? null : () => setState(() => input = input.isEmpty ? '' : input.substring(0, input.length - 1)), icon: const Icon(Icons.backspace_outlined), label: const Text('FUTA'))), const SizedBox(width: 10), Expanded(child: FilledButton.icon(onPressed: busy ? null : () => send(input.isEmpty ? '*123#' : input), icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded), label: Text(busy ? '…' : 'SEND')))]),
        ])),
      ])),
    );
  }
}
