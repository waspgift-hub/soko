import 'package:flutter/material.dart';

import '../../services/buyer_request_service.dart';
import '../../widgets/google_loading.dart';

class AdminBuyerRequestsScreen extends StatefulWidget {
  const AdminBuyerRequestsScreen({super.key});

  @override
  State<AdminBuyerRequestsScreen> createState() => _AdminBuyerRequestsScreenState();
}

class _AdminBuyerRequestsScreenState extends State<AdminBuyerRequestsScreen> {
  final BuyerRequestService _service = BuyerRequestService();
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _stats = const {};
  List<dynamic> _items = const [];
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final dash = await _service.adminDashboard();
      final list = await _service.adminList(status: _statusFilter);
      if (!mounted) return;
      setState(() {
        _stats = dash;
        _items = (list['items'] as List?) ?? const [];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _moderate(String id, String action) async {
    try {
      await _service.adminModerate(id, action: action, reason: 'admin action');
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(appBar: AppBar(title: const Text('Buyer Requests (Admin)')), body: const Center(child: GoogleLoading()));
    return Scaffold(
      appBar: AppBar(title: const Text('Buyer Requests (Admin)')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Dashboard', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text('Total: ${_stats['requests']?['total'] ?? 0}'),
                    Text('Active: ${_stats['requests']?['active'] ?? 0}'),
                    Text('Expired: ${_stats['requests']?['expired'] ?? 0}'),
                    Text('Closed: ${_stats['requests']?['closed'] ?? 0}'),
                    Text('Completed: ${_stats['requests']?['completed'] ?? 0}'),
                    Text('Offers: ${_stats['offers'] ?? 0}'),
                    Text('Views: ${_stats['views'] ?? 0}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [null, 'active', 'expired', 'closed', 'completed', 'suspended']
                  .map((s) => ChoiceChip(
                        label: Text(s ?? 'all'),
                        selected: _statusFilter == s,
                        onSelected: (_) { setState(() => _statusFilter = s); _load(); },
                      ))
                  .toList(),
            ),
            const SizedBox(height: 8),
            ..._items.map((raw) {
              final r = raw as Map<String, dynamic>;
              final id = r['id']?.toString() ?? '';
              return Card(
                child: ListTile(
                  title: Text(r['title']?.toString() ?? ''),
                  subtitle: Text('${r['status']} • ${r['offersCount']}/${r['offerLimit']} offers • ${r['viewCount']} views'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (a) => _moderate(id, a),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'suspend', child: Text('Suspend')),
                      PopupMenuItem(value: 'restore', child: Text('Restore')),
                      PopupMenuItem(value: 'close', child: Text('Close')),
                      PopupMenuItem(value: 'extend', child: Text('Extend')),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}