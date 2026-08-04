import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import '../../services/api_config.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/google_loading.dart';
import '../../widgets/soko_vibe_states.dart';

/// Admin view of everything ClickPesa knows: account balances, collections
/// (payments/deposits) and disbursements (payouts/withdrawals). Mirrors the
/// ClickPesa merchant dashboard so the admin can audit without leaving the app.
class AdminClickPesaScreen extends StatefulWidget {
  final bool embedded;

  const AdminClickPesaScreen({super.key, this.embedded = false});

  @override
  State<AdminClickPesaScreen> createState() => _AdminClickPesaScreenState();
}

class _AdminClickPesaScreenState extends State<AdminClickPesaScreen> {
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _balances = [];
  List<Map<String, dynamic>> _payments = [];
  List<Map<String, dynamic>> _payouts = [];
  int _paymentsTotal = 0;
  int _payoutsTotal = 0;
  Map<String, dynamic> _paymentsSummary = {};
  Map<String, dynamic> _payoutsSummary = {};
  DateTime? _asOf;

  String _type = 'all';
  String _status = '';
  String _channel = '';

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
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/api/admin/clickpesa/transactions',
      ).replace(queryParameters: {
        'type': _type,
        if (_status.isNotEmpty) 'status': _status,
        if (_channel.isNotEmpty) 'channel': _channel,
        'limit': '200',
      });
      final resp = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}');
      }
      final result = jsonDecode(resp.body) as Map<String, dynamic>;
      if (result['success'] != true) {
        throw Exception(result['error'] ?? 'Failed');
      }
      if (!mounted) return;
      setState(() {
        _balances = ((result['balances'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final pay = result['payments'] as Map<String, dynamic>? ?? {};
        final po = result['payouts'] as Map<String, dynamic>? ?? {};
        _payments = ((pay['data'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _payouts = ((po['data'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _paymentsTotal = (pay['totalCount'] as num?)?.toInt() ?? _payments.length;
        _payoutsTotal = (po['totalCount'] as num?)?.toInt() ?? _payouts.length;
        _paymentsSummary =
            Map<String, dynamic>.from(pay['summary'] as Map? ?? {});
        _payoutsSummary =
            Map<String, dynamic>.from(po['summary'] as Map? ?? {});
        _asOf = DateTime.tryParse(result['asOf'] as String? ?? '');
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _exportCsv() {
    final buffer = StringBuffer();
    buffer.writeln(
      'Type,Status,Amount,Currency,Channel,Provider,Reference,Phone,Date',
    );
    for (final p in _payments) {
      buffer.writeln(
        '"payment","${p['status'] ?? ''}","${p['collectedAmount'] ?? ''}",'
        '"${p['collectedCurrency'] ?? ''}","${p['channel'] ?? ''}","",'
        '"${p['orderReference'] ?? p['id'] ?? ''}",'
        '"${_customerPhone(p)}","${p['createdAt'] ?? ''}"',
      );
    }
    for (final p in _payouts) {
      buffer.writeln(
        '"payout","${p['status'] ?? ''}","${p['amount'] ?? ''}",'
        '"${p['currency'] ?? ''}","${p['channel'] ?? ''}","${p['channelProvider'] ?? ''}",'
        '"${p['orderReference'] ?? p['id'] ?? ''}",'
        '"${_beneficiaryPhone(p)}","${p['createdAt'] ?? ''}"',
      );
    }
    FirebaseFirestore.instance.collection('admin_exports').add({
      'type': 'clickpesa_csv',
      'data': buffer.toString(),
      'createdAt': FieldValue.serverTimestamp(),
      'exportedBy': FirebaseAuth.instance.currentUser?.uid,
      'filters': {'type': _type, 'status': _status, 'channel': _channel},
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.tr('users_csv_saved'))),
    );
  }

  String _customerPhone(Map<String, dynamic> p) {
    final c = p['customer'];
    if (c is Map && c['customerPhoneNumber'] != null) {
      return c['customerPhoneNumber'].toString();
    }
    return p['paymentPhoneNumber']?.toString() ?? '';
  }

  String _beneficiaryPhone(Map<String, dynamic> p) {
    final b = p['beneficiary'];
    if (b is Map && b['beneficiaryMobileNumber'] != null) {
      return b['beneficiaryMobileNumber'].toString();
    }
    if (b is Map && b['accountNumber'] != null) {
      return b['accountNumber'].toString();
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody();
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('clickpesa_overview')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _buildBody() {
    if (_loading) return const GoogleLoadingPage();
    if (_error != null) {
      return SokoVibeErrorState(
        message: _error,
        onRetry: _load,
      );
    }
    final nf = NumberFormat('#,###', 'en');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _buildFilterCard(),
          const SizedBox(height: 12),
          _buildBalanceCard(nf),
          const SizedBox(height: 12),
          _buildSummaryCard(nf),
          const SizedBox(height: 12),
          _buildTransactionHeader(nf),
          _buildTransactionList(nf),
        ],
      ),
    );
  }

  Widget _buildFilterCard() {
    final channels = <String>{
      for (final p in _payments) p['channel']?.toString() ?? '',
      for (final p in _payouts) p['channel']?.toString() ?? '',
    }..remove('');
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.filter_alt, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  '${context.tr('clickpesa_overview')} \u2022 ${_asOf != null ? DateFormat('MMM dd HH:mm').format(_asOf!) : ''}',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'all',
                  label: Text(context.tr('clickpesa_all')),
                ),
                ButtonSegment(
                  value: 'payments',
                  label: Text(context.tr('clickpesa_deposits')),
                ),
                ButtonSegment(
                  value: 'payouts',
                  label: Text(context.tr('clickpesa_withdrawals')),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (s) {
                setState(() => _type = s.first);
                _load();
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _statusDropdown(cs),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _channelDropdown(cs, channels),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusDropdown(ColorScheme cs) {
    final statuses = [
      '',
      'SUCCESS',
      'SETTLED',
      'PROCESSING',
      'PENDING',
      'FAILED',
    ];
    final labels = {
      '': context.tr('clickpesa_all'),
      'SUCCESS': context.tr('clickpesa_success'),
      'SETTLED': context.tr('clickpesa_settled'),
      'PROCESSING': context.tr('clickpesa_processing'),
      'PENDING': context.tr('clickpesa_pending'),
      'FAILED': context.tr('clickpesa_failed'),
    };
    return DropdownButtonFormField<String>(
      initialValue: _status,
      decoration: InputDecoration(
        labelText: context.tr('status'),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: statuses
          .map((s) => DropdownMenuItem(value: s, child: Text(labels[s]!)))
          .toList(),
      onChanged: (v) {
        setState(() => _status = v ?? '');
        _load();
      },
    );
  }

  Widget _channelDropdown(ColorScheme cs, Set<String> channels) {
    return DropdownButtonFormField<String>(
      initialValue: _channel.isEmpty ? '' : _channel,
      decoration: InputDecoration(
        labelText: context.tr('clickpesa_channel'),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        const DropdownMenuItem(value: '', child: Text('')),
        ...channels.map(
          (c) => DropdownMenuItem(value: c, child: Text(c)),
        ),
      ],
      onChanged: (v) {
        setState(() => _channel = v ?? '');
        _load();
      },
    );
  }

  Widget _balanceCard(NumberFormat nf) {
    final cs = Theme.of(context).colorScheme;
    if (_balances.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_balance_wallet, color: cs.tertiary),
                const SizedBox(width: 8),
                Text(
                  context.tr('clickpesa_balance'),
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: _balances.map((b) {
                final cur = b['currency'] ?? '';
                final amt = (b['balance'] as num?)?.toDouble() ?? 0;
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: cs.tertiary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$cur ${nf.format(amt.round())}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: cs.tertiary,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceCard(NumberFormat nf) {
    return _balanceCard(nf);
  }

  Widget _buildSummaryCard(NumberFormat nf) {
    final cs = Theme.of(context).colorScheme;
    final paySum = _paymentsSummary['total'] as num? ?? 0;
    final poSum = _payoutsSummary['total'] as num? ?? 0;
    final byStatus = (_paymentsSummary['byStatus'] as Map?)?.cast<String, num>();
    final byChannel =
        (_paymentsSummary['byChannel'] as Map?)?.cast<String, num>();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('revenue_breakdown'),
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            _row(
              context.tr('clickpesa_deposits'),
              paySum.toDouble(),
              cs.primary,
              nf,
            ),
            const SizedBox(height: 4),
            _row(
              context.tr('clickpesa_withdrawals'),
              poSum.toDouble(),
              cs.error,
              nf,
            ),
            if (byStatus != null && byStatus.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(thickness: 2),
              ),
              Text(
                context.tr('status'),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              for (final e in byStatus.entries)
                _row(
                  _statusLabel(e.key),
                  e.value.toDouble(),
                  cs.onSurface,
                  nf,
                ),
            ],
            if (byChannel != null && byChannel.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(thickness: 2),
              ),
              Text(
                context.tr('clickpesa_channel'),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              for (final e in byChannel.entries)
                _row(
                  e.key,
                  e.value.toDouble(),
                  cs.onSurface,
                  nf,
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _statusLabel(String key) {
    final labels = {
      'SUCCESS': context.tr('clickpesa_success'),
      'SETTLED': context.tr('clickpesa_settled'),
      'PROCESSING': context.tr('clickpesa_processing'),
      'PENDING': context.tr('clickpesa_pending'),
      'FAILED': context.tr('clickpesa_failed'),
    };
    return labels[key] ?? key;
  }

  Widget _row(
    String label,
    double amount,
    Color color,
    NumberFormat nf,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          '${nf.format(amount.round())} TZS',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildTransactionHeader(NumberFormat nf) {
    final total = _type == 'payouts'
        ? _payoutsTotal
        : _type == 'payments'
            ? _paymentsTotal
            : _paymentsTotal + _payoutsTotal;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          context.tr('transactions'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (total > 0)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  nf.format(total),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.download_rounded, size: 20),
              tooltip: context.tr('clickpesa_export'),
              onPressed: (_payments.isEmpty && _payouts.isEmpty)
                  ? null
                  : _exportCsv,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTransactionList(NumberFormat nf) {
    final rows = <_CpRow>[
      for (final p in _payments)
        _CpRow(
          kind: 'payment',
          status: p['status']?.toString() ?? '',
          amount: (p['collectedAmount'] as num?)?.toDouble() ?? 0,
          currency: p['collectedCurrency']?.toString() ?? 'TZS',
          channel: p['channel']?.toString() ?? '',
          provider: '',
          reference: p['orderReference']?.toString() ?? p['id']?.toString() ?? '',
          phone: _customerPhone(p),
          name: _customerName(p),
          date: p['createdAt']?.toString() ?? '',
        ),
      for (final p in _payouts)
        _CpRow(
          kind: 'payout',
          status: p['status']?.toString() ?? '',
          amount: (p['amount'] as num?)?.toDouble() ?? 0,
          currency: p['currency']?.toString() ?? 'TZS',
          channel: p['channel']?.toString() ?? '',
          provider: p['channelProvider']?.toString() ?? '',
          reference: p['orderReference']?.toString() ?? p['id']?.toString() ?? '',
          phone: _beneficiaryPhone(p),
          name: _beneficiaryName(p),
          date: p['createdAt']?.toString() ?? '',
        ),
    ];

    if (rows.isEmpty) {
      return SokoVibeEmptyState(
        icon: Icons.account_balance_outlined,
        title: context.tr('clickpesa_no_data'),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          _CpRowCard(row: rows[i], nf: nf),
          if (i != rows.length - 1) const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        Center(
          child: Text(
            '${context.tr('clickpesa_total')}: ${_paymentsTotal + _payoutsTotal}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  String _customerName(Map<String, dynamic> p) {
    final c = p['customer'];
    if (c is Map && c['customerName'] != null) return c['customerName'].toString();
    return '';
  }

  String _beneficiaryName(Map<String, dynamic> p) {
    final b = p['beneficiary'];
    if (b is Map && b['accountName'] != null) return b['accountName'].toString();
    return '';
  }
}

class _CpRow {
  final String kind;
  final String status;
  final double amount;
  final String currency;
  final String channel;
  final String provider;
  final String reference;
  final String phone;
  final String name;
  final String date;

  const _CpRow({
    required this.kind,
    required this.status,
    required this.amount,
    required this.currency,
    required this.channel,
    required this.provider,
    required this.reference,
    required this.phone,
    required this.name,
    required this.date,
  });
}

class _CpRowCard extends StatelessWidget {
  final _CpRow row;
  final NumberFormat nf;

  const _CpRowCard({required this.row, required this.nf});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isPayout = row.kind == 'payout';
    final statusColor = _statusColor(row.status, cs);
    final date = DateTime.tryParse(row.date);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isPayout ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 18,
                  color: isPayout ? cs.error : cs.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    row.reference,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    row.status,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${row.currency} ${nf.format(row.amount.round())}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isPayout ? cs.error : cs.primary,
              ),
            ),
            const SizedBox(height: 4),
            if (row.channel.isNotEmpty)
              Text(
                [
                  row.channel,
                  if (row.provider.isNotEmpty) row.provider,
                ].join(' \u2022 '),
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                ),
              ),
            if (row.name.isNotEmpty || row.phone.isNotEmpty)
              Text(
                [if (row.name.isNotEmpty) row.name, if (row.phone.isNotEmpty) row.phone]
                    .join(' \u2022 '),
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                ),
              ),
            if (date != null)
              Text(
                DateFormat('MMM dd, yyyy HH:mm').format(date),
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status, ColorScheme cs) {
    switch (status.toUpperCase()) {
      case 'SUCCESS':
      case 'SETTLED':
        return cs.primary;
      case 'PROCESSING':
      case 'PENDING':
        return cs.tertiary;
      case 'FAILED':
      case 'REVERSED':
      case 'REFUNDED':
      case 'UNAUTHORIZED':
        return cs.error;
      default:
        return cs.onSurfaceVariant;
    }
  }
}
