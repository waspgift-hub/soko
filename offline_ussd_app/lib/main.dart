import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const OfflineUssdApp());

class OfflineUssdApp extends StatelessWidget {
  const OfflineUssdApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Soko Langu Offline USSD',
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.green),
    home: const PairPage(),
  );
}

class PairPage extends StatefulWidget {
  const PairPage({super.key});
  @override State<PairPage> createState() => _PairPageState();
}

class _PairPageState extends State<PairPage> {
  final url = TextEditingController();
  final token = TextEditingController();
  String status = 'Weka PC URL na token';
  bool busy = false;

  Future<void> pair() async {
    setState(() { busy = true; status = 'Inaunganisha...'; });
    try {
      var base = url.text.trim();
      if (!base.startsWith('http://') && !base.startsWith('https://')) base = 'http://$base';
      final res = await http.post(Uri.parse('$base/pair'), headers: {
        'Content-Type': 'application/json', 'X-Pair-Token': token.text.trim(),
      }, body: '{}').timeout(const Duration(seconds: 8));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 200 || data['sessionId'] == null) throw Exception(data['error'] ?? 'Pairing failed');
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => UssdPage(base: base, token: token.text.trim(), sessionId: data['sessionId'].toString())));
    } catch (e) {
      setState(() => status = 'Imeshindikana: $e');
    } finally { if (mounted) setState(() => busy = false); }
  }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Soko Langu • Offline USSD')),
    body: ListView(padding: const EdgeInsets.all(24), children: [
      const Icon(Icons.router, size: 72),
      const SizedBox(height: 12),
      const Text('PC na simu ziwe kwenye Wi‑Fi/router moja. Internet haihitajiki.', textAlign: TextAlign.center),
      const SizedBox(height: 24),
      TextField(controller: url, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'PC URL', hintText: 'http://192.168.1.10:8787', border: OutlineInputBorder())),
      const SizedBox(height: 14),
      TextField(controller: token, decoration: const InputDecoration(labelText: 'Pairing token', border: OutlineInputBorder())),
      const SizedBox(height: 18),
      FilledButton.icon(onPressed: busy ? null : pair, icon: const Icon(Icons.link), label: Text(busy ? 'Inaunganisha...' : 'CONNECT')),
      const SizedBox(height: 16),
      Text(status, textAlign: TextAlign.center),
    ]),
  );
}

class UssdPage extends StatefulWidget {
  final String base, token, sessionId;
  const UssdPage({super.key, required this.base, required this.token, required this.sessionId});
  @override State<UssdPage> createState() => _UssdPageState();
}

class _UssdPageState extends State<UssdPage> {
  String title = 'SOKO LANGU';
  String text = 'Bonyeza START kuanza';
  String input = '';
  bool busy = false;

  Future<void> send(String code) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final res = await http.post(Uri.parse('${widget.base}/ussd'), headers: {
        'Content-Type': 'application/json', 'X-Pair-Token': widget.token,
      }, body: jsonEncode({'sessionId': widget.sessionId, 'code': code})).timeout(const Duration(seconds: 8));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 200) throw Exception(data['error'] ?? 'USSD error');
      setState(() { title = (data['title'] ?? 'SOKO LANGU').toString(); text = (data['text'] ?? '').toString(); input = ''; });
    } catch (e) { setState(() => text = 'Connection error: $e'); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Widget key(String value) => Expanded(child: Padding(padding: const EdgeInsets.all(5), child: FilledButton.tonal(onPressed: () => setState(() => input += value), child: Text(value, style: const TextStyle(fontSize: 22)))));

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('USSD Session'), actions: [IconButton(onPressed: () => send('*123#'), icon: const Icon(Icons.home))]),
    body: Column(children: [
      Container(width: double.infinity, margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(18), decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), color: Theme.of(context).colorScheme.surfaceContainerHighest), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 12), Text(text), const SizedBox(height: 14), Text('Chaguo: $input', style: const TextStyle(fontWeight: FontWeight.bold))]),
      const Spacer(),
      Row(children: [key('1'), key('2'), key('3')]),
      Row(children: [key('4'), key('5'), key('6')]),
      Row(children: [key('7'), key('8'), key('9')]),
      Row(children: [key('*'), key('0'), key('#')]),
      Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 18), child: Row(children: [Expanded(child: OutlinedButton(onPressed: () => setState(() => input = ''), child: const Text('CLEAR'))), const SizedBox(width: 10), Expanded(child: FilledButton(onPressed: busy ? null : () => send(input.isEmpty ? '*123#' : input), child: Text(busy ? '...' : 'SEND')))])),
    ]),
  );
}
