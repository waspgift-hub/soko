import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../extensions/context_tr.dart';
import '../../models/sponsored_campaign.dart';
import '../../services/sponsored_service.dart';
import '../../theme/app_colors.dart';

enum _AdminAdsView { overview, campaigns, settings }

class AdminAdsManagementScreen extends StatefulWidget {
  final bool embedded;
  const AdminAdsManagementScreen({super.key, this.embedded = false});

  @override
  State<AdminAdsManagementScreen> createState() => _AdminAdsManagementScreenState();
}

class _AdminAdsManagementScreenState extends State<AdminAdsManagementScreen> {
  final SponsoredService _service = SponsoredService();
  final NumberFormat _nf = NumberFormat('#,###', 'en');

  _AdminAdsView _view = _AdminAdsView.overview;
  AdminSponsoredSummary _summary = AdminSponsoredSummary();
  List<SponsoredCampaign> _campaigns = [];
  SponsoredLimits _limits = SponsoredLimits();
  String? _statusFilter;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final metrics = await _service.adminMetrics();
      final campaigns = await _service.adminListCampaigns(status: _statusFilter);
      final limits = await _service.adminGetLimits();
      if (!mounted) return;
      setState(() {
        _summary = metrics.summary;
        _campaigns = campaigns;
        _limits = limits;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _reloadCampaigns() async {
    try {
      final campaigns = await _service.adminListCampaigns(status: _statusFilter);
      if (mounted) setState(() => _campaigns = campaigns);
    } catch (_) {}
  }

  Future<void> _runAction(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('admin_action_done'))),
        );
      }
      await _reloadCampaigns();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? _buildError()
            : _buildBody();
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('admin_sponsored_settings'))),
      body: body,
    );
  }

  Widget _buildError() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: cs.error, size: 40),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: Text(context.tr('retry'))),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<_AdminAdsView>(
                  segments: [
                    ButtonSegment(value: _AdminAdsView.overview, label: Text(context.tr('dashboard')), icon: const Icon(Icons.dashboard_outlined, size: 16)),
                    ButtonSegment(value: _AdminAdsView.campaigns, label: Text(context.tr('admin_campaigns')), icon: const Icon(Icons.campaign_outlined, size: 16)),
                    ButtonSegment(value: _AdminAdsView.settings, label: Text(context.tr('admin_sponsored_settings')), icon: const Icon(Icons.settings_outlined, size: 16)),
                  ],
                  selected: {_view},
                  onSelectionChanged: (s) => setState(() => _view = s.first),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _load,
              ),
            ],
          ),
        ),
        Expanded(child: _buildSection()),
      ],
    );
  }

  Widget _buildSection() {
    switch (_view) {
      case _AdminAdsView.overview:
        return _buildOverview();
      case _AdminAdsView.campaigns:
        return _buildCampaigns();
      case _AdminAdsView.settings:
        return _buildSettings();
    }
  }

  // ── Overview ────────────────────────────────────────────────────────────

  Widget _buildOverview() {
    final cs = Theme.of(context).colorScheme;
    final ctr = _summary.ctr;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 2.1,
          children: [
            _statCard(cs, Icons.campaign_outlined, context.tr('admin_total_campaigns'), '${_summary.totalCampaigns}'),
            _statCard(cs, Icons.play_circle_outline, context.tr('active_campaigns'), '${_summary.activeCampaigns}'),
            _statCard(cs, Icons.pending_outlined, context.tr('admin_pending_campaigns'), '${_summary.pendingCampaigns}'),
            _statCard(cs, Icons.block_outlined, context.tr('admin_rejected_campaigns'), '${_summary.rejectedCampaigns}'),
            _statCard(cs, Icons.visibility_outlined, context.tr('analytics_impressions'), _nf.format(_summary.totalImpressions)),
            _statCard(cs, Icons.touch_app_outlined, context.tr('analytics_clicks'), _nf.format(_summary.totalClicks)),
            _statCard(cs, Icons.percent_outlined, context.tr('analytics_ctr'), '${(ctr * 100).toStringAsFixed(2)}%'),
            _statCard(cs, Icons.attach_money_rounded, context.tr('total_spend'), 'TZS ${_nf.format(_summary.totalSpendTzs.toInt())}'),
            _statCard(cs, Icons.account_balance_wallet_outlined, context.tr('revenue'), 'TZS ${_nf.format(_summary.totalRevenueTzs.toInt())}'),
          ],
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          icon: const Icon(Icons.sync_rounded, size: 18),
          label: Text(context.tr('admin_sweep_now')),
          onPressed: () => _runAction(_service.adminSweep),
        ),
      ],
    );
  }

  Widget _statCard(ColorScheme cs, IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: cs.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: cs.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Campaigns ───────────────────────────────────────────────────────────

  static const List<String?> _filters = [
    null,
    'active',
    'paused',
    'draft',
    'payment_pending',
    'rejected',
    'expired',
    'out_of_budget',
    'completed',
    'cancelled',
  ];

  Widget _buildCampaigns() {
    return Column(
      children: [
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _filters.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final f = _filters[i];
              final selected = _statusFilter == f;
              return FilterChip(
                label: Text(f == null ? context.tr('admin_filter_all') : _statusLabel(f)),
                selected: selected,
                onSelected: (_) {
                  setState(() => _statusFilter = f);
                  _reloadCampaigns();
                },
              );
            },
          ),
        ),
        Expanded(
          child: _campaigns.isEmpty
              ? Center(child: Text(context.tr('admin_no_campaigns')))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _campaigns.length,
                    itemBuilder: (context, i) => _campaignTile(_campaigns[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _campaignTile(SponsoredCampaign c) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = _statusColor(cs, c.status);
    final remaining = (c.totalBudgetTzs - c.spendTzs);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (c.storeName != null)
                        Text('${context.tr('admin_store')}: ${c.storeName}', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(_statusLabel(c.status), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                _metric(Icons.attach_money_rounded, 'TZS ${_nf.format(c.totalBudgetTzs.toInt())}', cs),
                _metric(Icons.savings_outlined, '${_nf.format(remaining.isNegative ? 0 : remaining.toInt())} ${context.tr('analytics_remaining_budget')}', cs),
                _metric(Icons.visibility_outlined, _nf.format(c.impressions), cs),
                _metric(Icons.touch_app_outlined, _nf.format(c.clicks), cs),
                _metric(Icons.percent_outlined, c.impressions > 0 ? '${(c.clicks / c.impressions * 100).toStringAsFixed(2)}%' : '0.00%', cs),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(_placementLabel(c.placement), style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.history, size: 16),
                  label: Text(context.tr('admin_audit_log')),
                  onPressed: () => _showAuditLog(c.id),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _actionButtons(c),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(IconData icon, String text, ColorScheme cs) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: cs.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ],
    );
  }

  List<Widget> _actionButtons(SponsoredCampaign c) {
    final buttons = <Widget>[];
    switch (c.status) {
      case 'draft':
      case 'payment_pending':
        buttons.add(_actionButton(context.tr('admin_approve_campaign'), Icons.check_circle_outline, () => _confirm(c, 'admin_approve_campaign', () => _service.adminApprove(c.id))));
        buttons.add(_actionButton(context.tr('admin_reject_campaign'), Icons.block, () => _rejectDialog(c)));
        break;
      case 'active':
        buttons.add(_actionButton(context.tr('admin_pause_campaign'), Icons.pause_circle_outline, () => _confirm(c, 'admin_pause_campaign', () => _service.adminPause(c.id))));
        buttons.add(_actionButton(context.tr('admin_end_campaign'), Icons.stop_circle_outlined, () => _confirm(c, 'admin_end_campaign', () => _service.adminEnd(c.id))));
        buttons.add(_actionButton(context.tr('admin_reject_campaign'), Icons.block, () => _rejectDialog(c)));
        break;
      case 'paused':
        buttons.add(_actionButton(context.tr('admin_resume_campaign'), Icons.play_circle_outline, () => _confirm(c, 'admin_resume_campaign', () => _service.adminResume(c.id))));
        buttons.add(_actionButton(context.tr('admin_end_campaign'), Icons.stop_circle_outlined, () => _confirm(c, 'admin_end_campaign', () => _service.adminEnd(c.id))));
        break;
    }
    return buttons;
  }

  Widget _actionButton(String label, IconData icon, VoidCallback onTap) {
    return OutlinedButton.icon(
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
    );
  }

  Future<void> _confirm(SponsoredCampaign c, String titleKey, Future<void> Function() action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr(titleKey)),
        content: Text(c.name),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('confirm'))),
        ],
      ),
    );
    if (ok == true) await _runAction(action);
  }

  Future<void> _rejectDialog(SponsoredCampaign c) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('admin_reject_campaign')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(c.name),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: context.tr('admin_reject_reason'),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('admin_reject_campaign')),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _runAction(() => _service.adminReject(c.id, reason: reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim()));
    }
  }

  Future<void> _showAuditLog(String campaignId) async {
    showDialog<void>(
      context: context,
      builder: (ctx) => FutureBuilder<SponsoredCampaign?>(
        future: _service.adminGetCampaign(campaignId),
        builder: (ctx, snap) {
          final logs = snap.data?.auditLogs ?? const <CampaignAuditLog>[];
          return AlertDialog(
            title: Text(context.tr('admin_audit_log')),
            content: SizedBox(
              width: double.maxFinite,
              child: snap.connectionState == ConnectionState.waiting
                  ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
                  : logs.isEmpty
                      ? Text(context.tr('admin_no_campaigns'))
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: logs.length,
                          itemBuilder: (_, i) {
                            final log = logs[i];
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(log.actorType == 'admin' ? Icons.admin_panel_settings : Icons.history, size: 18),
                              title: Text(log.action, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                '${DateFormat('yyyy-MM-dd HH:mm').format(log.createdAt)} · ${log.actorType}',
                                style: const TextStyle(fontSize: 11),
                              ),
                            );
                          },
                        ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('close'))),
            ],
          );
        },
      ),
    );
  }

  // ── Settings ────────────────────────────────────────────────────────────

  Widget _buildSettings() {
    return _SettingsEditor(
      limits: _limits,
      onSave: (minBudget, maxBudget, minDuration, maxDuration) async {
        await _service.adminUpdateSetting('sponsored_min_budget_tzs', '$minBudget');
        await _service.adminUpdateSetting('sponsored_max_budget_tzs', '$maxBudget');
        await _service.adminUpdateSetting('sponsored_min_duration_days', '$minDuration');
        await _service.adminUpdateSetting('sponsored_max_duration_days', '$maxDuration');
        await _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.tr('admin_settings_saved'))),
          );
        }
      },
    );
  }

  // ── Labels/colors ───────────────────────────────────────────────────────

  String _statusLabel(String status) {
    switch (status) {
      case 'draft':
        return context.tr('campaign_draft');
      case 'payment_pending':
        return context.tr('campaign_pending_payment');
      case 'active':
        return context.tr('campaign_active');
      case 'paused':
        return context.tr('campaign_paused');
      case 'completed':
        return context.tr('campaign_completed');
      case 'cancelled':
        return context.tr('campaign_cancelled');
      case 'rejected':
        return context.tr('campaign_rejected');
      case 'expired':
        return context.tr('campaign_expired');
      case 'out_of_budget':
        return context.tr('campaign_out_of_budget');
      default:
        return status;
    }
  }

  Color _statusColor(ColorScheme cs, String status) {
    switch (status) {
      case 'active':
        return cs.successGreen;
      case 'payment_pending':
        return cs.tertiary;
      case 'paused':
        return cs.secondary;
      case 'completed':
        return cs.primary;
      case 'cancelled':
      case 'rejected':
        return cs.error;
      case 'expired':
      case 'out_of_budget':
        return cs.onSurfaceVariant;
      default:
        return cs.onSurfaceVariant;
    }
  }

  String _placementLabel(String placement) {
    switch (placement) {
      case 'search':
        return context.tr('placement_sponsored_search');
      case 'category':
        return context.tr('placement_sponsored_category');
      case 'recommendations':
        return context.tr('placement_sponsored_recommendations');
      case 'product_feed':
        return context.tr('placement_sponsored_product_feed');
      case 'store_discovery':
        return context.tr('placement_sponsored_store_discovery');
      case 'featured':
        return context.tr('placement_featured_sponsored');
      default:
        return placement;
    }
  }
}

class _SettingsEditor extends StatefulWidget {
  final SponsoredLimits limits;
  final Future<void> Function(int minBudget, int maxBudget, int minDuration, int maxDuration) onSave;

  const _SettingsEditor({required this.limits, required this.onSave});

  @override
  State<_SettingsEditor> createState() => _SettingsEditorState();
}

class _SettingsEditorState extends State<_SettingsEditor> {
  late TextEditingController _minBudget;
  late TextEditingController _maxBudget;
  late TextEditingController _minDuration;
  late TextEditingController _maxDuration;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _minBudget = TextEditingController(text: '${widget.limits.minBudgetTzs}');
    _maxBudget = TextEditingController(text: '${widget.limits.maxBudgetTzs}');
    _minDuration = TextEditingController(text: '${widget.limits.minDurationDays}');
    _maxDuration = TextEditingController(text: '${widget.limits.maxDurationDays}');
  }

  @override
  void dispose() {
    _minBudget.dispose();
    _maxBudget.dispose();
    _minDuration.dispose();
    _maxDuration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(context.tr('admin_pricing_config'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cs.onSurface)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _field(_minBudget, context.tr('admin_min_budget'))),
            const SizedBox(width: 12),
            Expanded(child: _field(_maxBudget, context.tr('admin_max_budget'))),
          ],
        ),
        const SizedBox(height: 16),
        Text(context.tr('admin_placement_config'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cs.onSurface)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _field(_minDuration, context.tr('admin_min_duration'))),
            const SizedBox(width: 12),
            Expanded(child: _field(_maxDuration, context.tr('admin_max_duration'))),
          ],
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined, size: 18),
          label: Text(context.tr('save')),
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }

  Widget _field(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  Future<void> _save() async {
    final minBudget = int.tryParse(_minBudget.text.trim());
    final maxBudget = int.tryParse(_maxBudget.text.trim());
    final minDuration = int.tryParse(_minDuration.text.trim());
    final maxDuration = int.tryParse(_maxDuration.text.trim());
    if (minBudget == null || maxBudget == null || minDuration == null || maxDuration == null) return;
    if (minBudget <= 0 || maxBudget < minBudget || minDuration <= 0 || maxDuration < minDuration) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(minBudget, maxBudget, minDuration, maxDuration);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
