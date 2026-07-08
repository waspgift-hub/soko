import 'package:async/async.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../services/seller_earnings_service.dart';
import '../../models/transaction_model.dart';
import '../../models/withdrawal_model.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/google_loading.dart';
import '../../utils/phone_utils.dart';
import '../../theme/app_colors.dart';

class SellerEarningsScreen extends StatefulWidget {
  const SellerEarningsScreen({super.key});

  @override
  State<SellerEarningsScreen> createState() => _SellerEarningsScreenState();
}

class _SellerEarningsScreenState extends State<SellerEarningsScreen> {
  final _service = SellerEarningsService();
  final _phoneController = TextEditingController();
  bool _withdrawing = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final nf = NumberFormat('#,###', 'en');
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('earnings_dashboard')),
        centerTitle: true,
      ),
      body: uid.isEmpty
          ? Center(child: Text(context.tr('not_logged_in')))
          : RefreshIndicator(
              onRefresh: () async => setState(() {}),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  _buildBalanceCard(cs, nf),
                  const SizedBox(height: 12),
                  _buildSalesRow(cs, nf),
                  const SizedBox(height: 20),
                  _buildFeeInfoCard(cs, nf),
                  const SizedBox(height: 20),
                  _buildWithdrawalCard(cs, nf),
                  const SizedBox(height: 24),
                  _buildSectionTitle(context.tr('recent_transactions'), cs),
                  const SizedBox(height: 8),
                  _buildTransactionsList(cs, nf),
                  const SizedBox(height: 24),
                  _buildSectionTitle(context.tr('withdrawal_history'), cs),
                  const SizedBox(height: 8),
                  _buildWithdrawalHistory(cs, nf),
                ],
              ),
            ),
    );
  }

  Widget _buildBalanceCard(ColorScheme cs, NumberFormat nf) {
    return StreamBuilder<List<dynamic>>(
      stream: StreamZip([_service.streamSellerBalance(), _service.streamSellerTotalWithdrawn()]),
      builder: (context, snap) {
        final data = snap.data ?? [0, 0];
        final balance = (data[0] as num).toDouble();
        final withdrawn = (data[1] as num).toDouble();
        final totalEarned = balance + withdrawn;
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [cs.successGreen, cs.primary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: cs.successGreen.withValues(alpha: 0.24),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('inapatikana_kutoa'),
                style: TextStyle(
                  color: cs.surface.withValues(alpha: 0.78),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'TZS ${nf.format(balance)}',
                style: TextStyle(
                  color: cs.surface,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('jumla_ya_mapato_yote'),
                          style: TextStyle(
                            color: cs.surface.withValues(alpha: 0.78),
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          'TZS ${nf.format(totalEarned)}',
                          style: TextStyle(
                            color: cs.surface,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          context.tr('imetolewa'),
                          style: TextStyle(
                            color: cs.surface.withValues(alpha: 0.78),
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          'TZS ${nf.format(withdrawn)}',
                          style: TextStyle(
                            color: cs.surface,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSalesRow(ColorScheme cs, NumberFormat nf) {
    return Row(
      children: [
        Expanded(
          child: StreamBuilder<int>(
            stream: _service.streamTotalSales(),
            builder: (context, snap) {
              final count = snap.data ?? 0;
              return _infoCard(
                icon: Icons.receipt_long,
                label: context.tr('total_sales'),
                value: '$count',
                color: cs.tertiary,
                    cs: cs,
                  );
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StreamBuilder<double>(
            stream: _service.streamGrossSalesVolume(),
            builder: (context, snap) {
              final volume = snap.data ?? 0;
              return _infoCard(
                icon: Icons.trending_up,
                label: context.tr('gross_volume'),
                value: 'TZS ${nf.format(volume)}',
                color: cs.secondary,
                    cs: cs,
                  );
            },
          ),
        ),
      ],
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required ColorScheme cs,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.20),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withValues(alpha: 0.63),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeeInfoCard(ColorScheme cs, NumberFormat nf) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: cs.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                context.tr('fee_breakdown_per_sale'),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _feeRow(
            context.tr('product_price'),
            context.tr('full_amount_paid_by_buyer'),
            cs,
            nf,
          ),
          const SizedBox(height: 6),
          _feeRow(
            context.tr('processing_fee'),
            context.tr('mongike_fee_per_transaction'),
            cs,
            nf,
            deduct: true,
          ),
          const SizedBox(height: 6),
          _feeRow(
            context.tr('soko_vibe_commission'),
            context.tr('commission_percentage'),
            cs,
            nf,
            deduct: true,
          ),
          const SizedBox(height: 6),
          Divider(color: cs.outlineVariant, height: 16),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: cs.primary, size: 18),
                const SizedBox(width: 8),
                  Text(
                    context.tr('net_earnings_formula'),
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.63),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _feeRow(String label, String subtitle, ColorScheme cs, NumberFormat nf, {bool deduct = false}) {
    return Row(
      children: [
        Icon(
          deduct ? Icons.remove_circle_outline : Icons.add_circle_outline,
          size: 16,
          color: deduct ? cs.error : cs.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: cs.onSurface),
              ),
              Text(
                subtitle,
                style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.47)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWithdrawalCard(ColorScheme cs, NumberFormat nf) {
    const minWithdraw = 5000;

    return StreamBuilder<double>(
      stream: _service.streamSellerBalance(),
      builder: (context, snap) {
        final balance = snap.data ?? 0;
        final canWithdraw = balance >= minWithdraw;

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cs.tertiaryContainer,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: cs.tertiaryContainer,
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.tertiaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.account_balance_wallet,
                      color: cs.primary.withValues(alpha: 0.85),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('payout'),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: cs.primary.withValues(alpha: 0.85),
                        ),
                      ),
                      Text(
                        'Tuma pesa kwa mobile money yako',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Namba ya Simu',
                  hintText: context.tr('phone_example'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.phone_android),
                  filled: true,
                  fillColor: cs.surface,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: canWithdraw && !_withdrawing
                      ? () => _processWithdrawal()
                      : null,
                  icon: _withdrawing
                      ? const GoogleLoading(size: 20, strokeWidth: 2)
                      : const Icon(Icons.send),
                  label: Text(
                    _withdrawing
                        ? 'Inachakata...'
                        : 'Toa Pesa Sasa',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canWithdraw ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.6),
                    foregroundColor: cs.surface,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              if (!canWithdraw)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Salio la chini TZS 5,000 linahitajika',
                    style: TextStyle(color: cs.error, fontSize: 12),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _processWithdrawal() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      _showError(context.tr('enter_phone'));
      return;
    }

    setState(() => _withdrawing = true);

    final user = FirebaseAuth.instance.currentUser;
    final error = await _service.requestWithdrawal(
      phone: phone,
      userName: user?.displayName ?? '',
    );

    if (mounted) {
      setState(() => _withdrawing = false);
      if (error != null) {
        _showError(error);
      } else {
        _phoneController.clear();
        _showSuccessWithdrawal();
      }
    }
  }

  void _showSuccessWithdrawal() {
    final cs = Theme.of(context).colorScheme;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.tr('withdrawal_success')),
        backgroundColor: cs.primary,
      ),
    );
  }

  void _showError(String msg) {
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: cs.error),
    );
  }

  Widget _buildSectionTitle(String title, ColorScheme cs) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: cs.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: cs.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildTransactionsList(ColorScheme cs, NumberFormat nf) {
    return StreamBuilder<List<MarketplaceTransaction>>(
      stream: _service.streamTransactions(),
      builder: (context, snap) {
        if (snap.hasError) {
          return _emptyCard(context.tr('error_loading_transactions'), cs);
        }
        final txns = snap.data ?? [];
        final completedTxns = txns.where((t) => t.status == TransactionStatus.completed).toList();
        if (completedTxns.isEmpty) {
          return _emptyCard(context.tr('no_transactions'), cs);
        }
        return Column(
          children: completedTxns.take(10).map((tx) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant, width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.tertiaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.shopping_bag, color: cs.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tx.productName,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${tx.buyerName} | ${DateFormat('dd/MM/yy').format(tx.createdAt)}',
                          style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.51)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Fee: -TZS ${nf.format(tx.processingFee)} | Soko Vibe: -TZS ${nf.format(tx.sokoLanguCommission)}',
                          style: TextStyle(fontSize: 11, color: cs.error.withValues(alpha: 0.7)),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'TZS ${nf.format(tx.sellerReceives)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: cs.primary.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
          )).toList(),
        );
      },
    );
  }

  Widget _buildWithdrawalHistory(ColorScheme cs, NumberFormat nf) {
    return StreamBuilder<List<WithdrawalRequest>>(
      stream: _service.streamWithdrawals(),
      builder: (context, snap) {
        if (snap.hasError) {
          return _emptyCard(context.tr('error_loading_withdrawals'), cs);
        }
        final withdrawals = snap.data ?? [];
        if (withdrawals.isEmpty) {
          return _emptyCard(context.tr('no_withdrawals'), cs);
        }
        return Column(
          children: withdrawals.map((w) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant, width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: w.status == WithdrawalStatus.completed
                          ? cs.tertiaryContainer
                          : cs.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      w.status == WithdrawalStatus.completed
                          ? Icons.check_circle
                          : Icons.cancel,
                      color: w.status == WithdrawalStatus.completed
                          ? cs.primary
                          : cs.error,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TZS ${nf.format(w.netAmount)} → ${PhoneUtils.formatForDisplay(w.phone)}',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          w.status == WithdrawalStatus.completed
                              ? 'Fee: TZS ${nf.format(w.fee)} | ${DateFormat('MMM dd, yyyy HH:mm').format(w.createdAt)}'
                              : 'Failed: ${w.failureReason ?? context.tr('unknown')}',
                          style: TextStyle(
                            fontSize: 11,
                            color: w.status == WithdrawalStatus.completed
                                ? cs.onSurface.withValues(alpha: 0.51)
                                : cs.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '-TZS ${nf.format(w.amount)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: cs.error,
                    ),
                  ),
                ],
              ),
            ),
          )).toList(),
        );
      },
    );
  }

  Widget _emptyCard(String message, ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            message,
            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.47)),
          ),
        ),
      ),
    );
  }
}
