import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import '../../services/mongike_service.dart';
import '../../services/api_config.dart';
import '../../utils/phone_utils.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/google_loading.dart';

class AdminWalletScreen extends StatefulWidget {
  final bool embedded;

  const AdminWalletScreen({super.key, this.embedded = false});

  @override
  State<AdminWalletScreen> createState() => _AdminWalletScreenState();
}

class _AdminWalletScreenState extends State<AdminWalletScreen> {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  final _phoneController = TextEditingController();
  bool _withdrawing = false;
  bool _loading = true;

  double _totalCommissions = 0;
  double _totalBoostRevenue = 0;
  double _totalAdminBalance = 0;
  double _availableBalance = 0;
  double _totalProcessed = 0;
  double _totalPayouts = 0;
  double _mongikeBalance = 0;
  double _actualMongikeBalance = 0;
  double _totalAdminWithdrawn = 0;

  @override
  void initState() {
    super.initState();
    _loadFinanceData();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadFinanceData() async {
    setState(() => _loading = true);
    try {
      // Try API first (gives actual Mongike balance if available)
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token != null) {
        final resp = await http
            .get(
              Uri.parse('${ApiConfig.baseUrl}/api/admin/finance-summary'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
            )
            .timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200) {
          final result = jsonDecode(resp.body);
          if (result['success'] == true) {
            if (mounted)
              setState(() {
                _totalCommissions =
                    (result['totalCommissions'] as num?)?.toDouble() ?? 0;
                _totalBoostRevenue =
                    (result['totalBoostRevenue'] as num?)?.toDouble() ?? 0;
                _totalAdminBalance =
                    (result['totalAdminBalance'] as num?)?.toDouble() ?? 0;
                _totalAdminWithdrawn =
                    (result['totalAdminWithdrawn'] as num?)?.toDouble() ?? 0;
                _availableBalance =
                    (result['availableBalance'] as num?)?.toDouble() ??
                    (_totalAdminBalance - _totalAdminWithdrawn);
                if (_availableBalance < 0) _availableBalance = 0;
                _totalProcessed =
                    (result['totalProcessed'] as num?)?.toDouble() ?? 0;
                _totalPayouts =
                    (result['totalPaidOut'] as num?)?.toDouble() ?? 0;
                _actualMongikeBalance =
                    (result['actualMongikeBalance'] as num?)?.toDouble() ?? 0;
                _mongikeBalance = _availableBalance;
              });
            if (mounted) setState(() => _loading = false);
            return;
          }
        }
      }
    } catch (_) {}

    // Fallback: Firestore direct calculations
    try {
      double commissions = 0;
      double boostRevenue = 0;
      final revSnap = await FirebaseFirestore.instance
          .collection('revenue_transactions')
          .get();
      for (final doc in revSnap.docs) {
        final d = doc.data();
        if (d['type'] == 'boost') {
          boostRevenue += (d['sokoLanguCommission'] as num?)?.toDouble() ?? 0;
        } else {
          commissions += (d['sokoLanguCommission'] as num?)?.toDouble() ?? 0;
        }
      }

      double processed = 0;
      final txSnap = await FirebaseFirestore.instance
          .collection('transactions')
          .get();
      for (final doc in txSnap.docs) {
        processed += (doc.data()['totalAmount'] as num?)?.toDouble() ?? 0;
      }

      double payouts = 0;
      final wSnap = await FirebaseFirestore.instance
          .collection('withdrawals')
          .get();
      for (final doc in wSnap.docs) {
        final d = doc.data();
        if (d['status'] == 'completed') {
          payouts += (d['netAmount'] ?? d['amount'] ?? 0).toDouble();
        }
      }

      final awSnap = await FirebaseFirestore.instance
          .collection('admin_withdrawals')
          .get();
      double adminPayouts = 0;
      double adminWithdrawn = 0;
      for (final doc in awSnap.docs) {
        final d = doc.data();
        if (d['status'] == 'completed') {
          adminPayouts += (d['netAmount'] ?? d['amount'] ?? 0).toDouble();
          adminWithdrawn += (d['amount'] ?? 0).toDouble();
        }
      }

      final totalBalance = commissions + boostRevenue;
      double mongikeBalanceCalc = processed - (payouts + adminPayouts);
      if (mongikeBalanceCalc < 0) mongikeBalanceCalc = 0;
      final available = totalBalance - adminWithdrawn;

      if (mounted) {
        setState(() {
          _totalCommissions = commissions;
          _totalBoostRevenue = boostRevenue;
          _totalAdminBalance = totalBalance;
          _totalAdminWithdrawn = adminWithdrawn;
          _availableBalance = available < 0 ? 0 : available;
          _totalProcessed = processed;
          _totalPayouts = payouts + adminPayouts;
          _mongikeBalance = mongikeBalanceCalc;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _withdraw() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      _showError(context.tr('enter_phone_withdraw'));
      return;
    }
    if (_availableBalance < 2001) {
      _showError(context.tr('withdraw_min_amount'));
      return;
    }

    setState(() => _withdrawing = true);
    try {
      final result = await MongikeService.adminWithdraw(
        userId: uid,
        amount: _availableBalance.round().toDouble(),
        phone: phone,
      );

      if (mounted) {
        _phoneController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${context.tr('withdrawal_success')} ${result['netAmount']} TZS \u2192 $phone',
            ),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
        _loadFinanceData();
      }
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _withdrawing = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nf = NumberFormat('#,###', 'en');
    final cs = Theme.of(context).colorScheme;

    final body = _loading
        ? const GoogleLoadingPage()
        : SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildBalanceCard(cs, nf),
                const SizedBox(height: 16),
                _buildBreakdownCard(cs, nf),
                const SizedBox(height: 16),
                _buildMongikeCard(cs, nf),
                const SizedBox(height: 20),
                _buildWithdrawCard(cs, nf),
                const SizedBox(height: 20),
                _buildWithdrawalHistory(cs, nf),
              ],
            ),
          );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('admin_wallet_title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadFinanceData,
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _buildBalanceCard(ColorScheme cs, NumberFormat nf) {
    return Card(
      elevation: 4,
      color: cs.secondary.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.account_balance_wallet, color: cs.secondary, size: 56),
            const SizedBox(height: 12),
            Text(
              context.tr('jumla_ya_mapato_yote'),
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              '${nf.format(_availableBalance.round())} TZS',
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.bold,
                color: cs.secondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${context.tr('inapatikana_kutoa')}: ${nf.format(_availableBalance.round())} TZS',
              style: TextStyle(
                color: cs.primary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${context.tr('jumla_ya_mapato_yote')}: ${nf.format(_totalAdminBalance.round())} TZS  |  ${context.tr('imetolewa')}: ${nf.format(_totalAdminWithdrawn.round())} TZS',
              style: TextStyle(
                color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBreakdownCard(ColorScheme cs, NumberFormat nf) {
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
            const Divider(),
            _row(
              context.tr('sales_commissions'),
              _totalCommissions,
              cs.primary,
              nf,
            ),
            const SizedBox(height: 4),
            _row(
              context.tr('boost_revenue'),
              _totalBoostRevenue,
              Colors.orange,
              nf,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(thickness: 2),
            ),
            _row(
              context.tr('jumla_ya_mapato_yote'),
              _totalAdminBalance,
              cs.onSurfaceVariant,
              nf,
            ),
            const SizedBox(height: 4),
            _row(
              context.tr('inapatikana_kutoa'),
              _availableBalance,
              cs.secondary,
              nf,
              bold: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMongikeCard(ColorScheme cs, NumberFormat nf) {
    final hasDiscrepancy =
        _actualMongikeBalance > 0 && _actualMongikeBalance != _mongikeBalance;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_balance, color: cs.tertiary),
                const SizedBox(width: 8),
                Text(
                  context.tr('payment_status_title'),
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const Divider(),
            _row(
              context.tr('total_via_mongike'),
              _totalProcessed,
              cs.tertiary,
              nf,
            ),
            const SizedBox(height: 8),
            _row(context.tr('total_payouts'), _totalPayouts, cs.error, nf),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(thickness: 2),
            ),
            _row(
              'Salio (Kitabu)',
              _mongikeBalance,
              cs.primary,
              nf,
              bold: true,
            ),
            if (_actualMongikeBalance > 0) ...[
              const SizedBox(height: 4),
              _row(
                'Salio (Mongike)',
                _actualMongikeBalance,
                hasDiscrepancy ? Colors.orange : cs.successGreen,
                nf,
                bold: true,
              ),
            ],
            if (hasDiscrepancy)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 14,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Mongike wallet: TZS ${nf.format(_actualMongikeBalance.round())}, '
                          'Kitabu: TZS ${nf.format(_mongikeBalance.round())}',
                          style: TextStyle(fontSize: 11, color: Colors.orange),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWithdrawCard(ColorScheme cs, NumberFormat nf) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('withdraw'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                hintText: context.tr('withdraw_phone_hint'),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.phone_android),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _availableBalance >= 2001 && !_withdrawing
                    ? _withdraw
                    : null,
                icon: _withdrawing
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: GoogleLoading(
                          size: 18,
                          strokeWidth: 2,
                          color: cs.surface,
                        ),
                      )
                    : const Icon(Icons.send),
                label: Text(
                  _withdrawing
                      ? context.tr('withdrawal_processing')
                      : context.tr('withdraw'),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.secondary,
                  foregroundColor: cs.surface,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            if (_availableBalance < 2001)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  context.tr('withdraw_min_amount'),
                  style: TextStyle(color: cs.error, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWithdrawalHistory(ColorScheme cs, NumberFormat nf) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('withdrawal_history'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('admin_withdrawals')
              .where('userId', isEqualTo: uid)
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, snap) {
            if (!snap.hasData)
              return const Padding(
                padding: EdgeInsets.all(32),
                child: GoogleLoading(size: 24, strokeWidth: 2),
              );
            final docs = snap.data!.docs;
            if (docs.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      context.tr('no_withdrawals'),
                      style: TextStyle(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ),
              );
            }
            return Column(
              children: docs.map((doc) {
                final d = doc.data() as Map<String, dynamic>;
                final amount = (d['amount'] as num? ?? 0).toDouble();
                final phone = d['phone'] as String? ?? '';
                final status = d['status'] as String? ?? 'processing';
                final ts = d['createdAt'] as Timestamp?;
                final date = ts?.toDate() ?? DateTime.now();
                final statusColors = {
                  'processing': cs.tertiary,
                  'completed': cs.primary,
                  'failed': cs.error,
                };
                return Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.history,
                      color:
                          statusColors[status] ??
                          cs.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                    title: Text(
                      '${nf.format(amount.round())} TZS \u2192 ${PhoneUtils.formatForDisplay(phone)}',
                    ),
                    subtitle: Text(
                      '${DateFormat('MMM dd, yyyy HH:mm').format(date)} \u2022 $status',
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _row(
    String label,
    double amount,
    Color color,
    NumberFormat nf, {
    bool bold = false,
  }) {
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
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            fontSize: bold ? 18 : 14,
            color: bold ? color : null,
          ),
        ),
      ],
    );
  }
}
