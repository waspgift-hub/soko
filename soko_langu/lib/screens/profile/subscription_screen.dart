import 'package:flutter/material.dart';
import '../../extensions/context_tr.dart';
import '../../services/subscription_service.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final _service = SubscriptionService();
  bool _loading = true;
  String? _error;
  UserSubscription? _current;
  List<SubscriptionPlan> _plans = const [];
  Map<String, dynamic>? _entitlements;

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
      final results = await Future.wait([
        _service.fetchSubscription(),
        _service.fetchPlans(),
        _service.fetchEntitlements(),
      ]);
      if (!mounted) return;
      setState(() {
        _current = results[0] as UserSubscription?;
        _plans = results[1] as List<SubscriptionPlan>;
        _entitlements = results[2] as Map<String, dynamic>?;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('subscription', 'Subscription'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(context.tr('current_plan', 'Current plan'), style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface)),
                              const SizedBox(height: 8),
                              Text(_current?.planId ?? 'FREE'),
                              Text('Status: ${_current?.status ?? 'FREE'}'),
                              if (_current?.nextBillingDate != null) Text('Next billing: ${_current!.nextBillingDate}'),
                              if (_current?.expiresAt != null) Text('Expires: ${_current!.expiresAt}'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(context.tr('available_plans', 'Available plans'), style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface)),
                      const SizedBox(height: 8),
                      ..._plans.map((p) => Card(
                            child: ListTile(
                              title: Text(p.name),
                              subtitle: Text('${p.price} ${p.currency}/${p.billingPeriod}'),
                              trailing: ElevatedButton(
                                onPressed: () async {
                                  final ok = await _service.startTrial(p.id);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(ok ? 'Trial started' : 'Failed')),
                                    );
                                    if (ok) _load();
                                  }
                                },
                                child: Text(context.tr('start_trial', 'Start trial')),
                              ),
                            ),
                          )),
                      if (_entitlements != null) ...[
                        const SizedBox(height: 16),
                        Text('Entitlements', style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface)),
                        const SizedBox(height: 8),
                        ..._entitlements!.entries.map((e) => ListTile(title: Text(e.key), trailing: Text('${e.value}'))),
                      ],
                    ],
                  ),
                ),
    );
  }
}
