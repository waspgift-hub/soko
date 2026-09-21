import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../models/sponsored_campaign.dart';
import '../../services/sponsored_service.dart';
import '../../app/routes.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/ds/ds.dart';
import '../../theme/app_colors.dart';

class SponsoredCampaignDetailScreen extends StatefulWidget {
  final String campaignId;

  const SponsoredCampaignDetailScreen({super.key, required this.campaignId});

  @override
  State<SponsoredCampaignDetailScreen> createState() => _SponsoredCampaignDetailScreenState();
}

class _SponsoredCampaignDetailScreenState extends State<SponsoredCampaignDetailScreen> {
  final SponsoredService _service = SponsoredService();
  SponsoredCampaign? _campaign;
  SponsoredMetrics? _metrics;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _service.getCampaign(widget.campaignId),
        _service.getCampaignMetrics(widget.campaignId),
      ]);
      if (mounted) {
        setState(() {
          _campaign = results[0] as SponsoredCampaign?;
          _metrics = results[1] as SponsoredMetrics?;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
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
        title: Text(context.tr('campaign_details')),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (_campaign?.status == 'draft')
            IconButton(icon: const Icon(Icons.payment_outlined), onPressed: () => _initiatePayment(cs, nf)),
          if (_campaign?.status == 'active')
            IconButton(icon: const Icon(Icons.pause_circle_outline), onPressed: _pauseCampaign),
          if (_campaign?.status == 'paused')
            IconButton(icon: const Icon(Icons.play_arrow), onPressed: _resumeCampaign),
          if (_campaign?.status != 'completed' && _campaign?.status != 'cancelled')
            IconButton(icon: const Icon(Icons.cancel_outlined), onPressed: _cancelCampaign),
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
                  : _campaign == null
                      ? const Center(child: CircularProgressIndicator())
                      : _buildContent(cs, nf),
        ),
      ),
    );
  }

  Widget _buildContent(ColorScheme cs, NumberFormat nf) {
    final c = _campaign!;
    final m = _metrics;
    final budgetUsed = c.totalBudgetTzs.toInt() > 0
        ? (c.spendTzs.toInt() / c.totalBudgetTzs.toInt()).clamp(0.0, 1.0)
        : 0.0;
    final statusColor = _statusColor(cs, c.status);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _statusBadge(cs, c, statusColor),
        const SizedBox(height: 16),
        DsCard(
          radius: 18,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: cs.onSurface)),
              const SizedBox(height: 16),
              _infoRow(cs, context.tr('placement'), c.placement),
              _infoRow(cs, context.tr('daily_budget'), 'TZS ${nf.format(c.dailyBudgetTzs.toInt())}'),
              _infoRow(cs, context.tr('total_budget'), 'TZS ${nf.format(c.totalBudgetTzs.toInt())}'),
              _infoRow(cs, context.tr('bid_amount'), 'TZS ${nf.format(c.bidAmountTzs.toInt())}'),
              _infoRow(cs, context.tr('start_date'), DateFormat.yMMMd().format(c.startsAt)),
              _infoRow(cs, context.tr('end_date'), DateFormat.yMMMd().format(c.expiresAt)),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(context.tr('performance'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.onSurface)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _metricCard(cs, Icons.visibility_outlined, '${m?.impressions ?? c.impressions}', context.tr('impressions'))),
            const SizedBox(width: 12),
            Expanded(child: _metricCard(cs, Icons.touch_app_outlined, '${m?.clicks ?? c.clicks}', context.tr('clicks'))),
            const SizedBox(width: 12),
            Expanded(child: _metricCard(cs, Icons.attach_money_rounded, 'TZS ${nf.format((m?.spendTzs ?? c.spendTzs).toInt())}', context.tr('spend'))),
          ],
        ),
        const SizedBox(height: 16),
        if (m != null && m.impressions > 0) ...[
          Text('${context.tr('ctr')}: ${(m.ctr * 100).toStringAsFixed(2)}%', style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
        ],
        LinearProgressIndicator(
          value: budgetUsed,
          backgroundColor: cs.surfaceContainerLow,
          color: cs.primary,
          minHeight: 8,
        ),
        const SizedBox(height: 4),
        Text('${context.tr('budget_used')}: ${nf.format((budgetUsed * 100).toInt())}%', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        const SizedBox(height: 24),
        if (c.payment != null) ...[
          Text(context.tr('payment_info'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.onSurface)),
          const SizedBox(height: 12),
          DsCard(
            radius: 12,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow(cs, context.tr('payment_status'), c.payment!.status),
                _infoRow(cs, context.tr('payment_method'), c.payment!.provider),
                _infoRow(cs, context.tr('amount'), 'TZS ${nf.format(c.payment!.amountTzs.toInt())}'),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _statusBadge(ColorScheme cs, SponsoredCampaign c, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        c.status.toUpperCase().replaceAll('_', ' '),
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  Widget _infoRow(ColorScheme cs, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface)),
        ],
      ),
    );
  }

  Widget _metricCard(ColorScheme cs, IconData icon, String value, String label) {
    return DsCard(
      radius: 12,
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Icon(icon, color: cs.primary, size: 20),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: cs.onSurface)),
          Text(label, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  Color _statusColor(ColorScheme cs, String status) {
    switch (status) {
      case 'active': return cs.successGreen;
      case 'draft': return cs.onSurfaceVariant;
      case 'payment_pending': return cs.tertiary;
      case 'paused': return cs.secondary;
      case 'completed': return cs.primary;
      case 'cancelled': return cs.error;
      default: return cs.onSurfaceVariant;
    }
  }

  Future<void> _initiatePayment(ColorScheme cs, NumberFormat nf) async {
    final phoneCtrl = TextEditingController();
    String selectedMethod = 'ussd_push';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          left: 24,
          right: 24,
          top: 24,
        ),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('payment_method'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.onSurface)),
            const SizedBox(height: 16),
            Text('TZS ${nf.format(_campaign!.totalBudgetTzs.toInt())}', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: cs.primary)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: selectedMethod,
              items: [
                DropdownMenuItem(value: 'ussd_push', child: Text(context.tr('ussd_push_method'))),
                DropdownMenuItem(value: 'billpay', child: Text(context.tr('billpay_method'))),
              ],
              onChanged: (v) => selectedMethod = v ?? 'ussd_push',
              decoration: InputDecoration(labelText: context.tr('payment_method'), border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: phoneCtrl,
              decoration: InputDecoration(labelText: context.tr('phone_number'), border: const OutlineInputBorder()),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                if (phoneCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                _service.initiatePayment(
                  campaignId: _campaign!.id,
                  phone: phoneCtrl.text.trim(),
                  paymentMethod: selectedMethod,
                ).then((_) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.tr('payment_initiated')), backgroundColor: Colors.green),
                  );
                  _load();
                }).catchError((e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$e'), backgroundColor: Colors.red),
                  );
                });
              },
              child: Text(context.tr('pay_and_activate')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pauseCampaign() async {
    try {
      await _service.pauseCampaign(_campaign!.id);
      _load();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _resumeCampaign() async {
    try {
      await _service.resumeCampaign(_campaign!.id);
      _load();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _cancelCampaign() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('cancel_campaign')),
        content: Text(context.tr('cancel_campaign_confirmation')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('cancel'))),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _service.cancelCampaign(_campaign!.id).then((_) {
                _load();
                context.push(AppRoutes.sponsoredDashboard);
              }).catchError((e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$e'), backgroundColor: Colors.red),
                );
              });
            },
            child: Text(context.tr('confirm')),
          ),
        ],
      ),
    );
  }
}
