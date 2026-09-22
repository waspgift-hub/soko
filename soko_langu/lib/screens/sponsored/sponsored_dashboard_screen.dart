import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../models/sponsored_campaign.dart';
import '../../services/sponsored_service.dart';
import '../../app/routes.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/ds/ds.dart';
import '../../widgets/soko_vibe_states.dart';
import '../../theme/app_colors.dart';

class SponsoredDashboardScreen extends StatefulWidget {
  const SponsoredDashboardScreen({super.key});

  @override
  State<SponsoredDashboardScreen> createState() => _SponsoredDashboardScreenState();
}

class _SponsoredDashboardScreenState extends State<SponsoredDashboardScreen> {
  final SponsoredService _service = SponsoredService();
  List<SponsoredCampaign> _campaigns = [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadCampaigns();
  }

  Future<void> _loadCampaigns() async {
    try {
      final campaigns = await _service.listCampaigns();
      if (mounted) {
        setState(() {
          _campaigns = campaigns;
          _error = null;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        // Keep the raw error, not `e.toString()`, so it can be translated
        // (e.g. ErrorKeys.poorNetwork) at render time.
        setState(() {
          _error = e;
          _loading = false;
        });
      }
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
        title: Text(context.tr('sponsored_dashboard')),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadCampaigns,
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
                  ? SokoVibeErrorState(
                      message: context.trError(_error),
                      onRetry: _loadCampaigns,
                    )
                  : _buildContent(cs, nf),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.sponsoredCreate),
        icon: const Icon(Icons.add),
        label: Text(context.tr('create_campaign')),
      ),
    );
  }

  Widget _buildContent(ColorScheme cs, NumberFormat nf) {
    if (_campaigns.isEmpty) {
      return Center(
        child: DsEmptyState(
          icon: Icons.campaign_outlined,
          title: context.tr('no_sponsored_campaigns'),
          actionLabel: context.tr('create_first_campaign'),
          onAction: () => context.push(AppRoutes.sponsoredCreate),
        ),
      );
    }

    final active = _campaigns.where((c) => c.isActive).length;
    final draft = _campaigns.where((c) => c.isDraft).length;
    final totalImpressions = _campaigns.fold(0, (sum, c) => sum + c.impressions);
    final totalClicks = _campaigns.fold(0, (sum, c) => sum + c.clicks);
    final totalSpend = _campaigns.fold(BigInt.zero, (sum, c) => sum + c.spendTzs);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSummary(cs, nf, active, draft, totalImpressions, totalClicks, totalSpend),
        const SizedBox(height: 20),
        Text(context.tr('analytics_visibility'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.onSurface)),
        const SizedBox(height: 12),
        _buildAnalyticsGrid(cs, nf, totalImpressions, totalClicks, totalSpend),
        const SizedBox(height: 8),
        Text(
          context.tr('attribution_disclaimer'),
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        Text(context.tr('my_campaigns'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.onSurface)),
        const SizedBox(height: 12),
        ..._campaigns.map((c) => _buildCampaignTile(cs, c, nf)),
      ],
    );
  }

  Widget _buildSummary(
    ColorScheme cs,
    NumberFormat nf,
    int active,
    int draft,
    int totalImpressions,
    int totalClicks,
    BigInt totalSpend,
  ) {
    return Row(
      children: [
        Expanded(child: _statCard(cs, Icons.campaign_outlined, '$active', context.tr('active_campaigns'))),
        const SizedBox(width: 12),
        Expanded(child: _statCard(cs, Icons.drafts_outlined, '$draft', context.tr('draft_campaigns'))),
        const SizedBox(width: 12),
        Expanded(child: _statCard(cs, Icons.data_thresholding_outlined, '$totalClicks', context.tr('analytics_clicks'))),
      ],
    );
  }

  Widget _buildAnalyticsGrid(
    ColorScheme cs,
    NumberFormat nf,
    int totalImpressions,
    int totalClicks,
    BigInt totalSpend,
  ) {
    final ctr = totalImpressions > 0 ? totalClicks / totalImpressions : 0.0;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.9,
      children: [
        _analyticsCard(cs, nf, Icons.visibility_outlined, context.tr('analytics_impressions'), nf.format(totalImpressions)),
        _analyticsCard(cs, nf, Icons.touch_app_outlined, context.tr('analytics_clicks'), nf.format(totalClicks)),
        _analyticsCard(cs, nf, Icons.percent_outlined, context.tr('analytics_ctr'), '${(ctr * 100).toStringAsFixed(2)}%'),
        _analyticsCard(cs, nf, Icons.attach_money_rounded, context.tr('analytics_amount_spent'), 'TZS ${nf.format(totalSpend.toInt())}'),
      ],
    );
  }

  Widget _statCard(ColorScheme cs, IconData icon, String value, String label) {
    return DsCard(
      radius: 16,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: cs.primary, size: 22),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: cs.primary)),
          Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _analyticsCard(ColorScheme cs, NumberFormat nf, IconData icon, String label, String value) {
    return DsCard(
      radius: 16,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: cs.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: cs.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCampaignTile(ColorScheme cs, SponsoredCampaign campaign, NumberFormat nf) {
    Color statusColor;
    IconData statusIcon;
    switch (campaign.status) {
      case 'active':
        statusColor = cs.successGreen;
        statusIcon = Icons.check_circle;
        break;
      case 'draft':
        statusColor = cs.onSurfaceVariant;
        statusIcon = Icons.drafts_outlined;
        break;
      case 'payment_pending':
        statusColor = cs.tertiary;
        statusIcon = Icons.pending_outlined;
        break;
      case 'paused':
        statusColor = cs.secondary;
        statusIcon = Icons.pause_circle_outline;
        break;
      case 'completed':
        statusColor = cs.primary;
        statusIcon = Icons.task_alt_outlined;
        break;
      case 'cancelled':
        statusColor = cs.error;
        statusIcon = Icons.cancel_outlined;
        break;
      default:
        statusColor = cs.onSurfaceVariant;
        statusIcon = Icons.help_outline;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DsCard(
        radius: 18,
        padding: const EdgeInsets.all(14),
        onTap: () => context.push('${AppRoutes.sponsoredCampaign}/${campaign.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    campaign.name,
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: cs.onSurface),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(statusIcon, size: 14, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        campaign.status.toUpperCase().replaceAll('_', ' '),
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: statusColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.visibility_outlined, size: 14, color: cs.onSurfaceVariant),
                Text(' ${nf.format(campaign.impressions)}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                const SizedBox(width: 16),
                Icon(Icons.touch_app_outlined, size: 14, color: cs.onSurfaceVariant),
                Text(' ${nf.format(campaign.clicks)}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                const SizedBox(width: 16),
                Icon(Icons.percent_outlined, size: 14, color: cs.onSurfaceVariant),
                Text(
                  campaign.impressions > 0
                      ? ' ${(campaign.clicks / campaign.impressions * 100).toStringAsFixed(2)}%'
                      : ' 0.00%',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.attach_money_rounded, size: 14, color: cs.onSurfaceVariant),
                Text(' ${nf.format(campaign.spendTzs.toInt())} ${context.tr('analytics_amount_spent')}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                const SizedBox(width: 16),
                Icon(Icons.savings_outlined, size: 14, color: cs.onSurfaceVariant),
                Text(
                  ' ${nf.format((campaign.totalBudgetTzs - campaign.spendTzs).isNegative == false ? (campaign.totalBudgetTzs - campaign.spendTzs).toInt() : 0)} ${context.tr('analytics_remaining_budget')}',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
            if (campaign.isActive) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: (campaign.totalBudgetTzs.toInt() > 0)
                    ? (campaign.spendTzs.toInt() / campaign.totalBudgetTzs.toInt()).clamp(0.0, 1.0)
                    : 0,
                backgroundColor: cs.surfaceContainerLow,
                color: cs.primary,
                borderRadius: BorderRadius.circular(4),
                minHeight: 4,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
