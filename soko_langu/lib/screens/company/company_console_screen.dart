import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../app/routes.dart';
import '../../services/api_config.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/ui_button.dart';

class CompanyConsoleScreen extends StatefulWidget {
  const CompanyConsoleScreen({super.key});

  @override
  State<CompanyConsoleScreen> createState() => _CompanyConsoleScreenState();
}

class _CompanyConsoleScreenState extends State<CompanyConsoleScreen> with SingleTickerProviderStateMixin {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _me;
  Map<String, dynamic>? _overview;
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
        setState(() => _loading = false);
        return;
      }
      final meRes = await http.get(Uri.parse('${ApiConfig.baseUrl}/api/v1/company/me'), headers: {'Authorization': 'Bearer $t'});
      if (meRes.statusCode != 200) {
        setState(() => _error = 'Imeshindikana kupakia data.');
        setState(() => _loading = false);
        return;
      }
      final me = jsonDecode(meRes.body) as Map<String, dynamic>;
      _me = (me['data'] is Map<String, dynamic>) ? me['data'] as Map<String, dynamic> : null;

      if (_me != null) {
        final headers = {'Authorization': 'Bearer $t'};

        final results = await Future.wait([
          http.get(Uri.parse('${ApiConfig.baseUrl}/api/v1/company/legal-entities'), headers: headers),
          http.get(Uri.parse('${ApiConfig.baseUrl}/api/v1/company/audit?limit=15'), headers: headers),
          http.get(Uri.parse('${ApiConfig.baseUrl}/api/v1/company/overview'), headers: headers),
        ]);

        final eData = jsonDecode(results[0].body) as Map<String, dynamic>;
        _entities = (eData['data'] as List?) ?? const [];

        final aData = jsonDecode(results[1].body) as Map<String, dynamic>;
        _audit = (aData['data'] as List?) ?? const [];

        if (results[2].statusCode == 200) {
          final oData = jsonDecode(results[2].body) as Map<String, dynamic>;
          _overview = (oData['data'] is Map<String, dynamic>) ? oData['data'] as Map<String, dynamic> : null;
        }
      }
    } catch (e) {
      _error = 'Mtandao: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final t = await _token();
      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/v1/company/bootstrap'),
        headers: {'Authorization': 'Bearer $t', 'Content-Type': 'application/json'},
      );
      if (res.statusCode >= 400) {
        final d = jsonDecode(res.body);
        setState(() => _error = d['error']?.toString() ?? 'Imeshindikana.');
        setState(() => _loading = false);
        return;
      }
      await _load();
    } catch (e) {
      setState(() => _error = 'Mtandao: $e');
      setState(() => _loading = false);
    }
  }

  Future<void> _createEntity() async {
    if (_name.text.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
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
        setState(() => _loading = false);
        return;
      }
      _name.clear();
      _regNo.clear();
      _taxId.clear();
      await _load();
    } catch (e) {
      setState(() => _error = 'Mtandao: $e');
      setState(() => _loading = false);
    }
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: UiColors.textSecondary)),
                  const SizedBox(height: 4),
                  Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAction(String title, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Theme.of(context).dividerColor),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 28),
              const SizedBox(height: 8),
              Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Company OS - Founder Command Center'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
            tooltip: 'Onyesha upya',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(UiSpace.md),
                children: [
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: UiColors.danger.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_error!, style: const TextStyle(color: UiColors.danger)),
                    ),
                    const SizedBox(height: UiSpace.md),
                  ],
                  if (_me == null) ...[
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Theme.of(context).dividerColor),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            const Icon(Icons.business, size: 48),
                            const SizedBox(height: 12),
                            Text('Huna membership ya Company OS', style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 8),
                            Text(
                              'Anza kwa kujiunga kama Founder ili kufungua Founder Command Center',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: UiColors.textSecondary),
                            ),
                            const SizedBox(height: 16),
                            UiPrimaryButton(label: 'Jiunge kama Founder', onPressed: _bootstrap),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    // User info
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                          child: Icon(Icons.person, color: Theme.of(context).colorScheme.onPrimaryContainer),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Karibu, Founder', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                              Text('Role: ${_me!['role']}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: UiColors.textSecondary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: UiSpace.lg),

                    // Stats Overview
                    Text('Muhtasari', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: UiSpace.sm),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;
                        final crossAxisCount = width > 900 ? 4 : (width > 600 ? 2 : 1);
                        final counts = _overview?['counts'] as Map<String, dynamic>? ?? {};
                        final items = [
                          ['Wafanyakazi', '${counts['employees'] ?? 0}', Icons.people, Colors.blue],
                          ['Miradi', '${counts['projects'] ?? 0}', Icons.work_outline, Colors.orange],
                          ['Kazi', '${counts['tasks'] ?? 0}', Icons.task_alt, Colors.purple],
                          ['Mashirika', '${counts['legal_entities'] ?? 0}', Icons.business, Colors.green],
                        ];
                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: width > 600 ? 2.5 : 2.8,
                          ),
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return _buildStatCard(item[0] as String, item[1] as String, item[2] as IconData, item[3] as Color);
                          },
                        );
                      },
                    ),
                    const SizedBox(height: UiSpace.lg),

                    // Tasks & Projects
                    if (_overview != null) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Theme.of(context).dividerColor),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.task_alt),
                                        const SizedBox(width: 8),
                                        Text('Kazi', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    _buildOverviewRow('Leo', '${(_overview!['tasks'] as Map)['due_today'] ?? 0}', Colors.blue),
                                    _buildOverviewRow('Zimechelewa', '${(_overview!['tasks'] as Map)['overdue'] ?? 0}', Colors.red),
                                    _buildOverviewRow('Zinaendelea', '${(_overview!['tasks'] as Map)['in_progress'] ?? 0}', Colors.orange),
                                    _buildOverviewRow('Zimekwama', '${(_overview!['tasks'] as Map)['blocked'] ?? 0}', Colors.deepOrange),
                                    _buildOverviewRow('Zimekamilika', '${(_overview!['tasks'] as Map)['completed'] ?? 0}', Colors.green),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Theme.of(context).dividerColor),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.work_outline),
                                        const SizedBox(width: 8),
                                        Text('Miradi', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    _buildOverviewRow('Inayoendelea', '${(_overview!['projects'] as Map)['active'] ?? 0}', Colors.blue),
                                    _buildOverviewRow('Katika Hatari', '${(_overview!['projects'] as Map)['at_risk'] ?? 0}', Colors.orange),
                                    _buildOverviewRow('Imekwama', '${(_overview!['projects'] as Map)['blocked'] ?? 0}', Colors.red),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: UiSpace.lg),

                      // Pending Approvals
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Theme.of(context).dividerColor),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.pending_actions),
                                  const SizedBox(width: 8),
                                  Text('Inasubiri Idhini', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _buildOverviewRow('Maombi ya Likizo', '${((_overview!['pending_approvals'] as Map)['leave'] ?? 0)}', Colors.amber),
                              _buildOverviewRow('Ankara Zilizowasilishwa', '${((_overview!['pending_approvals'] as Map)['invoices_submitted'] ?? 0)}', Colors.orange),
                              _buildOverviewRow('Gharama Zilizowasilishwa', '${((_overview!['pending_approvals'] as Map)['expenses_submitted'] ?? 0)}', Colors.deepOrange),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: UiSpace.lg),
                    ],

                    // Quick Actions
                    Text('Vitendo vya Haraka', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: UiSpace.sm),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1,
                      ),
                      itemCount: 6,
                      itemBuilder: (context, index) {
                        final actions = [
                          ['Wafanyakazi', Icons.people, () {}],
                          ['Miradi', Icons.work_outline, () {}],
                          ['Kazi', Icons.task_alt, () {}],
                          ['Fedha', Icons.account_balance_wallet, () {}],
                          ['Kalenda', Icons.calendar_today, () {}],
                          ['Hati', Icons.folder, () {}],
                        ];
                        final action = actions[index];
                        return _buildQuickAction(action[0] as String, action[1] as IconData, action[2] as VoidCallback);
                      },
                    ),
                    const SizedBox(height: UiSpace.lg),

                    // Legal Entities
                    Text('Vyombo vya Kisheria', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: UiSpace.sm),
                    if (_entities.isEmpty)
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Theme.of(context).dividerColor),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Hakuna vyombo vya kisheria vilivyoongezwa bado. Ongeza hapa chini.', style: TextStyle(color: UiColors.textSecondary)),
                        ),
                      )
                    else
                      ..._entities.map((e) => Card(
                            elevation: 0,
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Theme.of(context).dividerColor),
                            ),
                            child: ListTile(
                              leading: const Icon(Icons.business),
                              title: Text(e['name'] ?? ''),
                              subtitle: Text('Sarafu: ${e['currency'] ?? 'TZS'} | Kodi: ${e['tax_id'] ?? '-'}'),
                            ),
                          )),
                    const SizedBox(height: UiSpace.md),
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Theme.of(context).dividerColor),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Ongeza Shirika/Kampuni Mpya', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),
                            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Jina la kampuni', border: OutlineInputBorder())),
                            const SizedBox(height: 10),
                            TextField(controller: _regNo, decoration: const InputDecoration(labelText: 'Namba ya usajili (BRELA)', border: OutlineInputBorder())),
                            const SizedBox(height: 10),
                            TextField(controller: _taxId, decoration: const InputDecoration(labelText: 'Namba ya kodi (TIN)', border: OutlineInputBorder())),
                            const SizedBox(height: 12),
                            UiPrimaryButton(label: 'Ongeza Kampuni', onPressed: _createEntity),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: UiSpace.lg),

                    // Recent Activity
                    Text('Shughuli za Hivi Karibuni', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: UiSpace.sm),
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Theme.of(context).dividerColor),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            if (_audit.isEmpty)
                              const Text('Hakuna shughuli zilizorekodiwa bado.', style: TextStyle(color: UiColors.textSecondary))
                            else
                              ..._audit.take(10).map((a) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          margin: const EdgeInsets.only(top: 6, right: 10),
                                          decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(a['action']?.toString().replaceAll('.', ' ').toUpperCase() ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                              Text('${a['target_type']} • ${a['target_id']?.toString().substring(0, 8) ?? ''}', style: const TextStyle(fontSize: 12, color: UiColors.textSecondary)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  )),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildOverviewRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
