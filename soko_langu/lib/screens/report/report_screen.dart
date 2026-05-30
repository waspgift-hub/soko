import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/report_model.dart';
import '../../services/report_service.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/google_loading.dart';

class ReportScreen extends StatefulWidget {
  final String reportedUserId;
  final String reportedUserName;
  final String? productId;
  final String? productName;

  const ReportScreen({
    super.key,
    required this.reportedUserId,
    required this.reportedUserName,
    this.productId,
    this.productName,
  });

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final _reportService = ReportService();
  final _descriptionController = TextEditingController();
  String _selectedReason = 'fraud';
  bool _submitting = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (_descriptionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('fill_fields'))),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final report = Report(
        id: '',
        reporterId: user.uid,
        reporterName: user.displayName ?? 'Anonymous',
        reportedUserId: widget.reportedUserId,
        reportedUserName: widget.reportedUserName,
        productId: widget.productId,
        productName: widget.productName,
        reason: _selectedReason,
        description: _descriptionController.text.trim(),
        createdAt: DateTime.now(),
      );

      await _reportService.submitReport(report);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('report_submitted'))),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.tr('something_wrong')}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('report_user')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.productName != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.shopping_bag, color: cs.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.productName!,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              '${context.tr('seller')}: ${widget.reportedUserName}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              context.tr('report_reason'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            ...Report.reasons.map((reason) {
              return RadioListTile<String>(
                title: Text(_reasonLabel(context, reason)),
                value: reason,
                groupValue: _selectedReason,
                onChanged: (v) => setState(() => _selectedReason = v!),
                contentPadding: EdgeInsets.zero,
                dense: true,
              );
            }),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              maxLines: 5,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: context.tr('report_description_hint'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: GoogleLoading(size: 20, strokeWidth: 2),
                      )
                    : const Icon(Icons.flag),
                label: Text(_submitting ? context.tr('submitting') : context.tr('submit_report')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _reasonLabel(BuildContext context, String reason) {
    switch (reason) {
      case 'fraud': return context.tr('report_reason_fraud');
      case 'fake_product': return context.tr('report_reason_fake_product');
      case 'scam': return context.tr('report_reason_scam');
      case 'inappropriate': return context.tr('report_reason_inappropriate');
      case 'harassment': return context.tr('report_reason_harassment');
      case 'other': return context.tr('report_reason_other');
      default: return reason;
    }
  }
}
