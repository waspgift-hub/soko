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
        title: Text(newStatus == 'resolved' ? 'Resolve Report' : 'Dismiss Report'),
        content: TextField(
          controller: noteCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Admin note (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx, {
                'status': newStatus,
                'note': noteCtrl.text,
              });
            },
            child: Text(newStatus == 'resolved' ? 'Resolve' : 'Dismiss'),
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
    if (newStatus == 'resolved' || newStatus == 'dismissed') {
      _maybeSuspendUser(report);
    }
  }

  Future<void> _maybeSuspendUser(Report report) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Suspend User?'),
        content: Text('Suspend ${report.reportedUserName}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Suspend'),
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
          SnackBar(content: Text('${report.reportedUserName} suspended')),
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
                      Icon(Icons.flag, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(context.tr('no_reports'), style: TextStyle(color: Colors.grey[600])),
                    ],
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: () async {},
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
      selectedColor: Colors.red.withAlpha(30),
      checkmarkColor: Colors.red,
    );
  }

  Widget _buildReportCard(Report report) {
    final dateStr = DateFormat('MMM dd, yyyy HH:mm').format(report.createdAt);
    final statusColor = report.status == 'resolved'
        ? Colors.green
        : report.status == 'dismissed'
            ? Colors.grey
            : Colors.orange;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withAlpha(30),
          child: Icon(Icons.flag, color: statusColor, size: 20),
        ),
        title: Text(
          report.reportedUserName,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Text(
          '${_reasonLabel(report.reason)} • $dateStr',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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
                    color: Colors.grey.withAlpha(20),
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
                      color: Colors.blue.withAlpha(15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.withAlpha(50)),
                    ),
                    child: Text(
                      'Admin: ${report.adminNote}',
                      style: const TextStyle(fontSize: 13, color: Colors.blue),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(dateStr, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                const SizedBox(height: 8),
                if (report.status == 'pending')
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => _updateStatus(report, 'dismissed'),
                        icon: const Icon(Icons.close, size: 18),
                        label: Text(context.tr('dismiss')),
                        style: TextButton.styleFrom(foregroundColor: Colors.grey),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () => _updateStatus(report, 'resolved'),
                        icon: const Icon(Icons.check, size: 18),
                        label: Text(context.tr('resolve')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
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
                    backgroundColor: statusColor.withAlpha(20),
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
          Text('$label: ', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  String _reasonLabel(String reason) {
    switch (reason) {
      case 'fraud': return 'Fraud';
      case 'fake_product': return 'Fake Product';
      case 'scam': return 'Scam';
      case 'inappropriate': return 'Inappropriate';
      case 'harassment': return 'Harassment';
      case 'other': return 'Other';
      default: return reason;
    }
  }
}
