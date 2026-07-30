import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import '../../services/api_config.dart';
import '../../services/localization_service.dart';
import '../../widgets/google_loading.dart';
import '../../theme/app_colors.dart';

class SellerStatementScreen extends StatefulWidget {
  final String sellerId;
  const SellerStatementScreen({super.key, required this.sellerId});

  @override
  State<SellerStatementScreen> createState() => _SellerStatementScreenState();
}

class _SellerStatementScreenState extends State<SellerStatementScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  String _lang = 'sw';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) { _error = 'Unauthenticated'; return; }
      final resp = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/api/seller-statement/${widget.sellerId}'),
            headers: { 'Authorization': 'Bearer $token', 'Content-Type': 'application/json' },
          )
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) { _error = 'Server error: ${resp.statusCode}'; return; }
      final result = jsonDecode(resp.body);
      if (result['success'] != true) { _error = 'Failed to load statement'; return; }
      if (mounted) setState(() { _data = result; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Network error'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(context.tr('seller_statement', 'Seller Statement')),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Text(_lang == 'sw' ? 'EN' : 'SW', style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary, fontSize: 14)),
            onPressed: () => setState(() => _lang = _lang == 'sw' ? 'en' : 'sw'),
          ),
          IconButton(icon: const Icon(Icons.download), onPressed: _loading || _data == null ? null : _downloadStatement),
          IconButton(icon: const Icon(Icons.share), onPressed: _loading || _data == null ? null : _shareStatement),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: GoogleLoading())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: cs.error),
                      const SizedBox(height: 16),
                      Text(_error!, style: TextStyle(color: cs.error)),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _load, child: Text(context.tr('retry', 'Retry'))),
                    ],
                  ),
                )
              : _buildStatement(cs),
    );
  }

  Widget _buildStatement(ColorScheme cs) {
    final s = _data!;
    final seller = s['seller'] as Map<String, dynamic>;
    final summary = s['summary'] as Map<String, dynamic>;
    final entries = s['entries'] as List? ?? [];
    final generatedAt = DateTime.tryParse(s['generatedAt'] as String? ?? '') ?? DateTime.now();
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'en');
    final curFmt = NumberFormat('#,###', 'en');

    // Build statement data for QR code
    final qrData = jsonEncode({
      'title': s['statementTitle'],
      'generatedAt': s['generatedAt'],
      'seller': seller,
      'summary': summary,
      'entries': entries,
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      child: Column(
        children: [
          // Logo + Title
          _buildHeader(cs),
          const SizedBox(height: 20),

          // Seller Info
          _buildInfoCard(cs, seller, generatedAt, dateFmt),
          const SizedBox(height: 16),

          // Summary
          _buildSummaryRow(cs, summary, curFmt),
          const SizedBox(height: 16),

          // Transaction Table
          entries.isEmpty
              ? _buildEmptyState(cs)
              : _buildTransactionTable(cs, entries, curFmt, dateFmt),
          const SizedBox(height: 24),

          // QR Code
          _buildQrSection(cs, qrData),
          const SizedBox(height: 16),

          // Footer
          Text(
            context.tr('seller_statement_footer', 'Soko Vibe © {year} — This is an official financial statement').replaceAll('{year}', DateTime.now().year.toString()),
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs) {
    return Column(
      children: [
        Image.asset('assets/soko_vibe_logo.png', height: 56, errorBuilder: (_, _, _) =>
          Icon(Icons.store, size: 48, color: cs.primary)),
        const SizedBox(height: 8),
        Text(
          context.tr('app_name', 'SOKO VIBE'),
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 2, color: cs.primary),
        ),
        const SizedBox(height: 4),
        Text(
          context.tr('seller_statement_subtitle', 'SELLER STATEMENT'),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 3, color: cs.onSurface),
        ),
      ],
    );
  }

  Widget _buildInfoCard(ColorScheme cs, Map<String, dynamic> seller, DateTime generatedAt, DateFormat df) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${context.tr('info_name', 'NAME')}: ${seller['name'] ?? ''}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: cs.onSurface)),
          const SizedBox(height: 4),
          if ((seller['phone'] ?? '').isNotEmpty)
            Padding(padding: const EdgeInsets.only(bottom: 2), child: Text('${context.tr('info_phone', 'PHONE')}: ${seller['phone']}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))),
          if ((seller['email'] ?? '').isNotEmpty)
            Padding(padding: const EdgeInsets.only(bottom: 2), child: Text('${context.tr('info_email', 'EMAIL')}: ${seller['email']}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))),
          if ((seller['location'] ?? '').isNotEmpty)
            Text('${context.tr('info_location', 'LOCATION')}: ${seller['location']}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          const Divider(height: 16),
          Text('${context.tr('info_generated_at', 'GENERATED ON')}: ${df.format(generatedAt)}', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(ColorScheme cs, Map<String, dynamic> summary, NumberFormat cf) {
    final credits = (summary['totalCredits'] as num?)?.toDouble() ?? 0;
    final debits = (summary['totalDebits'] as num?)?.toDouble() ?? 0;
    final balance = (summary['currentBalance'] as num?)?.toDouble() ?? 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [cs.primary.withValues(alpha: 0.1), cs.primary.withValues(alpha: 0.05)]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _summaryItem(cs, context.tr('total_income', 'Total Income'), 'TSh ${cf.format(credits)}', cs.successGreen),
              const SizedBox(width: 12),
              _summaryItem(cs, context.tr('total_expenses', 'Total Expenses'), 'TSh ${cf.format(debits)}', cs.error),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: balance >= 0 ? cs.successGreen.withValues(alpha: 0.1) : cs.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(context.tr('current_balance', 'CURRENT BALANCE'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: balance >= 0 ? cs.successGreen : cs.error)),
                Text('TSh ${cf.format(balance)}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: balance >= 0 ? cs.successGreen : cs.error)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(ColorScheme cs, String label, String value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: color)),
        ],
      ),
    );
  }

  Widget _buildTransactionTable(ColorScheme cs, List entries, NumberFormat cf, DateFormat df) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('payment_history', 'PAYMENT HISTORY'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: cs.onSurface)),
          const SizedBox(height: 12),
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                SizedBox(width: 60, child: Text(context.tr('date_column', 'Date'), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: cs.primary))),
                Expanded(flex: 2, child: Text(context.tr('description_column', 'Description'), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: cs.primary))),
                SizedBox(width: 55, child: Text(context.tr('income_column', 'Income'), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: cs.primary), textAlign: TextAlign.right)),
                SizedBox(width: 55, child: Text(context.tr('expenses_column', 'Expenses'), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: cs.primary), textAlign: TextAlign.right)),
                SizedBox(width: 60, child: Text(context.tr('balance_column', 'Balance'), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: cs.primary), textAlign: TextAlign.right)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Table rows
          ...entries.asMap().entries.map((entry) {
            final i = entry.key;
            final e = entry.value as Map<String, dynamic>;
            final date = e['date'] != null ? DateTime.tryParse(e['date'] as String) : null;
            final isCredit = e['type'] == 'credit';
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              decoration: i.isOdd ? BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.15)) : null,
              child: Row(
                children: [
                  SizedBox(
                    width: 60,
                    child: Text(date != null ? DateFormat('dd/MM', 'en').format(date) : '-',
                        style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant))),
                  Expanded(
                    flex: 2,
                    child: Text((e['description']?.toString() ?? '').substring(0, ((e['description']?.toString() ?? '').length).clamp(0, 20)),
                        style: TextStyle(fontSize: 9, color: cs.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  SizedBox(
                    width: 55,
                    child: Text(isCredit ? 'TSh ${cf.format((e['netAmount'] as num?)?.toDouble() ?? 0)}' : '',
                        style: TextStyle(fontSize: 9, color: cs.successGreen, fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
                  SizedBox(
                    width: 55,
                    child: Text(!isCredit ? 'TSh ${cf.format((e['netAmount'] as num?)?.toDouble() ?? 0)}' : '',
                        style: TextStyle(fontSize: 9, color: cs.error, fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
                  SizedBox(
                    width: 60,
                    child: Text('TSh ${cf.format((e['runningBalance'] as num?)?.toDouble() ?? 0)}',
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: cs.onSurface), textAlign: TextAlign.right)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined, size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text(context.tr('no_payments_yet', 'No payments yet'), style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(context.tr('no_payments_subtitle', 'Financial details will appear once you start selling'), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant.withValues(alpha: 0.7))),
        ],
      ),
    );
  }

  Widget _buildQrSection(ColorScheme cs, String qrData) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(context.tr('scan_qr_full_info', 'SCAN QR CODE FOR FULL DETAILS'),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant, letterSpacing: 1)),
          const SizedBox(height: 12),
          QrImageView(
            data: qrData,
            version: QrVersions.auto,
            size: 180,
            backgroundColor: Colors.white,
            eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: cs.primary),
            dataModuleStyle: QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
          ),
          const SizedBox(height: 8),
          Text(context.tr('scan_qr_hint', 'Scan this QR code for all statement details'),
              style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant.withValues(alpha: 0.6))),
        ],
      ),
    );
  }

  Future<void> _shareStatement() async {
    if (_data == null) return;
    try {
      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/send-notification'),
        headers: { 'Content-Type': 'application/json' },
        body: jsonEncode({
          'userId': widget.sellerId,
          'title': context.tr('your_statement', 'Your Statement'),
          'body': context.tr('statement_ready_body', 'Your financial statement is ready. Check the app.'),
          'data': { 'type': 'statement' },
        }),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('statement_sent_notification', 'Statement sent via notification'))),
        );
      }
    } catch (_) {}
  }

  Future<void> _downloadStatement() async {
    if (_data == null) return;
    try {
      final jsonString = const JsonEncoder.withIndent('  ').convert(_data);
      late Directory dir;
      if (Platform.isAndroid) {
        final extDir = await getExternalStorageDirectory();
        dir = extDir != null ? Directory('${extDir.path}/Download') : await getApplicationDocumentsDirectory();
        if (extDir != null && !await dir.exists()) {
          await dir.create(recursive: true);
        }
      } else {
        dir = await getApplicationDocumentsDirectory();
      }
      final file = File('${dir.path}/soko_vibe_statement_${widget.sellerId.substring(0, 8)}.json');
      await file.writeAsString(jsonString);
      await OpenFile.open(file.path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('statement_saved', 'Statement saved')), duration: const Duration(seconds: 3)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${context.tr('error_label', 'Error')}: $e')));
      }
    }
  }
}
