import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/sponsored_campaign.dart';
import '../../services/sponsored_service.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/ds/ds.dart';

class SponsoredPerformanceScreen extends StatefulWidget {
  final String campaignId;

  const SponsoredPerformanceScreen({super.key, this.campaignId = ''});

  @override
  State<SponsoredPerformanceScreen> createState() => _SponsoredPerformanceScreenState();
}

class _SponsoredPerformanceScreenState extends State<SponsoredPerformanceScreen> {
  final SponsoredService _service = SponsoredService();
  SponsoredMetrics? _metrics;
  int _selectedDays = 30;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.campaignId.isEmpty) return;
    setState(() => _loading = true);
    try {
      final metrics = await _service.getCampaignMetrics(widget.campaignId, days: _selectedDays);
      if (mounted) setState(() => _metrics = metrics);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final nf = NumberFormat('#,###', 'en');

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(context.tr('sponsored_performance')),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          DropdownButton<int>(
            value: _selectedDays,
            items: [7, 30, 60, 90].map((d) => DropdownMenuItem(value: d, child: Text('$d ${context.tr('days_abbr')}'))).toList(),
            onChanged: (v) {
              if (v != null) {
                setState(() => _selectedDays = v);
                _load();
              }
            },
            dropdownColor: cs.surface,
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).brightness == Brightness.dark ? Colors.black : Colors.white,
              cs.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!))
                  : _buildContent(cs, nf),
        ),
      ),
    );
  }

  Widget _buildContent(ColorScheme cs, NumberFormat nf) {
    final m = _metrics;
    if (m == null) {
      return Center(child: DsEmptyState(icon: Icons.bar_chart_outlined, title: context.tr('no_metrics_yet')));
    }

    final ctr = m.ctr * 100;
    final cpc = (m.clicks > 0) ? (m.spendTzs.toInt() / m.clicks) : 0.0;
    final cpm = (m.impressions > 0) ? (m.spendTzs.toInt() / m.impressions * 1000) : 0.0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(child: _metricCard(cs, Icons.visibility_outlined, '${m.impressions}', context.tr('impressions'))),
            const SizedBox(width: 12),
            Expanded(child: _metricCard(cs, Icons.touch_app_outlined, '${m.clicks}', context.tr('clicks'))),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _metricCard(cs, Icons.attach_money_rounded, 'TZS ${nf.format(m.spendTzs.toInt())}', context.tr('total_spend'))),
            const SizedBox(width: 12),
            Expanded(child: _metricCard(cs, Icons.percent_outlined, '${ctr.toStringAsFixed(1)}%', context.tr('ctr'))),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _metricCard(cs, Icons.currency_pound_outlined, 'TZS ${nf.format(cpc.toInt())}', context.tr('cpc'))),
            const SizedBox(width: 12),
            Expanded(child: _metricCard(cs, Icons.currency_pound_outlined, 'TZS ${nf.format(cpm.toInt())}', context.tr('cpm'))),
          ],
        ),
        const SizedBox(height: 24),
        Text(context.tr('performance_over_time'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.onSurface)),
        const SizedBox(height: 12),
        DsCard(
          radius: 16,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${context.tr('last_days')}: $_selectedDays', style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              Text(context.tr('performance_chart_coming_soon'), style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _metricCard(ColorScheme cs, IconData icon, String value, String label) {
    return DsCard(
      radius: 12,
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Icon(icon, color: cs.primary, size: 20),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: cs.onSurface)),
          Text(label, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}
