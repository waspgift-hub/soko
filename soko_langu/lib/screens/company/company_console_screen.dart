import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../app/routes.dart';
import '../../services/api_config.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/ui_button.dart';
import '../../ui/widgets/ui_button.dart';

class CompanyConsoleScreen extends StatefulWidget {
  const CompanyConsoleScreen({super.key});

  @override
  State<CompanyConsoleScreen> createState() => _CompanyConsoleScreenState();
}

class _CompanyConsoleScreenState extends State<CompanyConsoleScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _me;
  List<dynamic> _entities = const [];
  List<dynamic> _audit = const [];

  final _name = TextEditingController();
  final _regNo = TextEditingController();
  final _taxId = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _regNo.dispose();
    _taxId.dispose();
    super.dispose();
  }

  Future<String?> _token() async => FirebaseAuth.instance.currentUser?.getIdToken();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final t = await _token();
      if (t == null) {
        setState(() => _error = 'Ingia akaunti kwanza.');
        return;
      }
      final meRes = await http.get(Uri.parse('${ApiConfig.baseUrl}/api/v1/company/me'), headers: {'Authorization': 'Bearer $t'});
      final me = jsonDecode(meRes.body) as Map<String, dynamic>;
      _me = (me['data'] is Map<String, dynamic>) ? me['data'] as Map<String, dynamic> : null;

      if (_me != null) {
        final eRes = await http.get(Uri.parse('${ApiConfig.baseUrl}/api/v1/company/legal-entities'), headers: {'Authorization': 'Bearer $t'});
        final eData = jsonDecode(eRes.body) as Map<String, dynamic>;
        _entities = (eData['data'] as List?) ?? const [];
        final aRes = await http.get(Uri.parse('${ApiConfig.baseUrl}/api/v1/company/audit?limit=20'), headers: {'Authorization': 'Bearer $t'});
        final aData = jsonDecode(aRes.body) as Map<String, dynamic>;
        _audit = (aData['data'] as List?) ?? const [];
      }
    } catch (e) {
      _error = 'Mtandao: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      final t = await _token();
      final res = await http.post(Uri.parse('${ApiConfig.baseUrl}/api/v1/company/bootstrap'), headers: {'Authorization': 'Bearer $t', 'Content-Type': 'application/json'});
      if (res.statusCode >= 400) {
        final d = jsonDecode(res.body);
        setState(() => _error = d['error']?.toString() ?? 'Imeshindikana.');
        return;
      }
      await _load();
    } catch (e) {
      setState(() => _error = 'Mtandao: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createEntity() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      final t = await _token();
      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/v1/company/legal-entities'),
        headers: {'Authorization': 'Bearer $t', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': _name.text.trim(),
          'registrationNumber': _regNo.text.trim(),
          'taxId': _taxId.text.trim(),
        }),
      );
      if (res.statusCode >= 400) {
        final d = jsonDecode(res.body);
        setState(() => _error = d['error']?.toString() ?? 'Imeshindikana.');
        return;
      }
      _name.clear();
      _regNo.clear();
      _taxId.clear();
      await _load();
    } catch (e) {
      setState(() => _error = 'Mtandao: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Company OS')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(UiSpace.md),
              children: [
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: UiColors.danger)),
                  const SizedBox(height: UiSpace.md),
                ],
                if (_me == null) ...[
                  const Text('Huna membership ya Company OS. Bonyeza kujiunga kama founder.'),
                  const SizedBox(height: UiSpace.md),
                  UiPrimaryButton(label: 'Jiunge kama founder', onPressed: _bootstrap),
                ] else ...[
                  Text('Role: ${_me!['role']}', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: UiSpace.lg),
                  Text('Vyombo vya kisheria', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: UiSpace.sm),
                  for (final e in _entities) ...[
                    Text('• ${e['name']} (${e['currency'] ?? 'TZS'})', style: Theme.of(context).textTheme.bodyMedium),
                  ],
                  const SizedBox(height: UiSpace.md),
                  TextField(controller: _name, decoration: const InputDecoration(labelText: 'Jina la kampuni', border: OutlineInputBorder())),
                  const SizedBox(height: UiSpace.sm),
                  TextField(controller: _regNo, decoration: const InputDecoration(labelText: 'Namba ya usajili', border: OutlineInputBorder())),
                  const SizedBox(height: UiSpace.sm),
                  TextField(controller: _taxId, decoration: const InputDecoration(labelText: 'Namba ya kodi (TIN)', border: OutlineInputBorder())),
                  const SizedBox(height: UiSpace.md),
                  UiPrimaryButton(label: 'Ongeza kampuni', onPressed: _createEntity),
                  const SizedBox(height: UiSpace.lg),
                  Text('Audit (20 za mwisho)', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: UiSpace.sm),
                  for (final a in _audit) ...[
                    Text('${a['action']} — ${a['target_type']}/${a['target_id']}', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ],
            ),
    );
  }
}
