import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../extensions/context_tr.dart';
import '../../services/api_config.dart';

class AdminSecurityScreen extends StatefulWidget {
  const AdminSecurityScreen({super.key});

  @override
  State<AdminSecurityScreen> createState() => _AdminSecurityScreenState();
}

class _AdminSecurityScreenState extends State<AdminSecurityScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _events = [];
  Map<String, dynamic> _summary = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('not signed in');
      final token = await user.getIdToken();
      final res = await http.get(
        Uri.parse(ApiConfig.v1('/admin/security/login-events?limit=100')),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 20));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 200 || body['success'] != true) {
        throw Exception(body['error'] ?? 'load_failed');
      }
      setState(() {
        _events = (body['events'] as List? ?? []).cast<Map<String, dynamic>>();
        _summary = (body['summary'] as Map? ?? {}).cast<String, dynamic>();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('admin_security')),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      _summaryCard(cs),
                      const SizedBox(height: 12),
                      ..._events.map(_eventTile),
                      if (_events.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(child: Text(context.tr('no_data'))),
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _summaryCard(ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            _stat('total', _summary['total']),
            _stat('success', _summary['success']),
            _stat('failed', _summary['failed']),
            _stat('otp_send_failed', _summary['otpSendFailed']),
            _stat('denied', _summary['denied']),
            _stat('new_devices', _summary['newDevices']),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, dynamic value) {
    return Chip(label: Text('$label: ${value ?? 0}'));
  }

  Widget _eventTile(Map<String, dynamic> e) {
    final outcome = e['outcome']?.toString() ?? '';
    final method = e['method']?.toString() ?? '';
    final when = e['createdAt']?.toString() ?? '';
    final newDevice = e['newDevice'] == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          outcome == 'success' ? Icons.check_circle : Icons.error_outline,
          color: outcome == 'success' ? Colors.green : Colors.red,
        ),
        title: Text('$method · $outcome${newDevice ? ' · NEW DEVICE' : ''}'),
        subtitle: Text('${e['device']} ${e['os']} ${e['browser']}\n${e['location']} · ${e['ip']}\n$when'),
        isThreeLine: true,
      ),
    );
  }
}