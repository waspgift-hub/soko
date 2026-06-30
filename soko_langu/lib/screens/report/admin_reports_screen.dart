import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../models/report_model.dart';
import '../../services/report_service.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/google_loading.dart';

class AdminReportsScreen extends StatefulWidget {
  final bool embedded;

  const AdminReportsScreen({super.key, this.embedded = false});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  final _reportService = ReportService();
  String _selectedFilter = 'pending';

  @override
  void initState() {
    super.initState();
  }

  Future<void> _updateStatus(Report report, String newStatus) async {
    final noteCtrl = TextEditingController();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(newStatus == 'resolved' ? context.tr('resolve_report') : context.tr('dismiss_report')),
        content: TextField(
          controller: noteCtrl,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: context.tr('admin_note_optional'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('cancel'))),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx, {
                'status': newStatus,
                'note': noteCtrl.text,
              });
            },
            child: Text(newStatus == 'resolved' ? context.tr('resolve') : context.tr('dismiss')),
          ),
        ],
      ),
    );
    if (result == null) return;
    await _reportService.updateReportStatus(
      report.id,
      result['status']!,
      adminNote: result['note'],
    );
    if (newStatus == 'resolved') {
      _maybeSuspendUser(report);
    }
  }

  Future<void> _maybeSuspendUser(Report report) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('suspend_user')),
        content: Text(context.tr('suspend_user_confirm').replaceAll('{name}', report.reportedUserName)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('no'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: Text(context.tr('suspend')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(report.reportedUserId)
          .update({'isSuspended': true});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('user_suspended').replaceAll('{name}', report.reportedUserName))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody();
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('reports'))),
      body: body,
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              _filterChip('pending', context.tr('pending')),
              const SizedBox(width: 8),
              _filterChip('resolved', context.tr('resolved')),
              const SizedBox(width: 8),
              _filterChip('', context.tr('all')),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Report>>(
            stream: _reportService.getReports(status: _selectedFilter.isEmpty ? null : _selectedFilter),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const GoogleLoadingPage();
              }
              final reports = snap.data ?? [];
              if (reports.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.flag, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(height: 16),
                      Text(context.tr('no_reports'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ],
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: () async => setState(() {}),
                child: ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: reports.length,
                  itemBuilder: (_, i) => _buildReportCard(reports[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _filterChip(String filter, String label) {
    final selected = _selectedFilter == filter;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _selectedFilter = filter),
      selectedColor: Theme.of(context).colorScheme.error.withValues(alpha: 0.12),
      checkmarkColor: Theme.of(context).colorScheme.error,
    );
  }

  Widget _buildReportCard(Report report) {
    final dateStr = DateFormat('MMM dd, yyyy HH:mm').format(report.createdAt);
    final statusColor = report.status == 'resolved'
        ? Theme.of(context).colorScheme.primary
        : report.status == 'dismissed'
            ? Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6)
            : Theme.of(context).colorScheme.tertiary;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: 0.12),
          child: Icon(Icons.flag, color: statusColor, size: 20),
        ),
        title: Text(
          report.reportedUserName,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Text(
          '${_reasonLabel(report.reason)} • $dateStr',
          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailRow(context.tr('seller'), report.reportedUserName),
                _detailRow(context.tr('reporter'), report.reporterName),
                if (report.productName != null)
                  _detailRow(context.tr('product'), report.productName!),
                _detailRow(context.tr('reason'), _reasonLabel(report.reason)),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    report.description,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                if (report.adminNote != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.20)),
                    ),
                    child: Text(
                      'Admin: ${report.adminNote}',
                      style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.secondary),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(dateStr, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6))),
                const SizedBox(height: 8),
                if (report.status == 'pending')
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => _updateStatus(report, 'dismissed'),
                        icon: const Icon(Icons.close, size: 18),
                        label: Text(context.tr('dismiss')),
                        style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () => _updateStatus(report, 'resolved'),
                        icon: const Icon(Icons.check, size: 18),
                        label: Text(context.tr('resolve')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Theme.of(context).colorScheme.surface,
                        ),
                      ),
                    ],
                  ),
                if (report.status != 'pending')
                  Chip(
                    label: Text(
                      report.status.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    backgroundColor: statusColor.withValues(alpha: 0.08),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text('$label: ', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  String _reasonLabel(String reason) {
    switch (reason) {
      case 'fraud': return context.tr('reason_fraud');
      case 'fake_product': return context.tr('reason_fake_product');
      case 'scam': return context.tr('reason_scam');
      case 'inappropriate': return context.tr('reason_inappropriate');
      case 'harassment': return context.tr('reason_harassment');
      case 'other': return context.tr('reason_other');
      default: return reason;
    }
  }
}
