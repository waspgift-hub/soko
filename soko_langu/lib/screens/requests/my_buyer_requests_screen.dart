import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../models/buyer_request_model.dart';
import '../../services/buyer_request_service.dart';


class MyBuyerRequestsScreen extends StatefulWidget {
  const MyBuyerRequestsScreen({super.key});

  @override
  State<MyBuyerRequestsScreen> createState() => _MyBuyerRequestsScreenState();
}

class _MyBuyerRequestsScreenState extends State<MyBuyerRequestsScreen> {
  final BuyerRequestService _service = BuyerRequestService();
  bool _loading = true;
  String? _error;
  List<BuyerRequest> _items = const [];
  Map<String, int> _counts = const {};
  String _category = 'all';

  static const _categories = <String>[
    'all', 'active', 'receiving_offers', 'limit_reached', 'expiring_soon', 'expired', 'completed', 'closed',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final page = await _service.listMine(category: _category);
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _counts = page.counts;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Buyer Requests')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.postBuyerRequest),
        icon: const Icon(Icons.add),
        label: const Text('New request'),
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: _categories.map((c) {
                final count = _counts[c] ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('$c${count > 0 ? ' ($count)' : ''}'),
                    selected: c == _category,
                    onSelected: (_) { setState(() => _category = c); _load(); },
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _items.isEmpty
                        ? const Center(child: Text('No requests yet'))
                        : ListView.builder(
                            itemCount: _items.length,
                            itemBuilder: (context, i) {
                              final r = _items[i];
                              return Card(
                                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                child: ListTile(
                                  title: Text(r.title),
                                  subtitle: Text('TZS ${r.minBudget}-${r.maxBudget} • ${r.offersCount}/${r.offerLimit} offers • ${r.viewCount} views'),
                                  trailing: Text(r.status),
                                  onTap: () => context.push('/buyer-requests/${r.id}'),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}