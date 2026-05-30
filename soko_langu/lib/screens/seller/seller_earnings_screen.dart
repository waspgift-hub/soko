import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../services/seller_earnings_service.dart';
import '../../models/transaction_model.dart';
import '../../models/withdrawal_model.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/google_loading.dart';

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
          ? const Center(child: Text('Not logged in'))
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
    return StreamBuilder<double>(
      stream: _service.streamSellerBalance(),
      builder: (context, snap) {
        final balance = snap.data ?? 0;
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF065535), Color(0xFF0B8043)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF065535).withAlpha(60),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Current Balance',
                    style: TextStyle(
                      color: Colors.white.withAlpha(200),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'TZS ${nf.format(balance)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Available for withdrawal',
                style: TextStyle(
                  color: Colors.white.withAlpha(180),
                  fontSize: 13,
                ),
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
                label: 'Total Sales',
                value: '$count',
                color: Colors.orange,
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
                label: 'Gross Volume',
                value: 'TZS ${nf.format(volume)}',
                color: Colors.blue,
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
        color: color.withAlpha(12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withAlpha(50),
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
              color: cs.onSurface.withAlpha(160),
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
                'Fee Breakdown per Sale',
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
            'Product Price',
            'Full amount paid by buyer',
            cs,
            nf,
          ),
          const SizedBox(height: 6),
          _feeRow(
            'Mongike Fee',
            'Fixed TZS 180 per transaction',
            cs,
            nf,
            deduct: true,
          ),
          const SizedBox(height: 6),
          _feeRow(
            'Soko Langu Commission',
            '4% of product price',
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
                Icon(Icons.check_circle, color: Colors.green.shade600, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Net Earnings Formula: Price - (Price × 4%) - 180',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withAlpha(160),
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
          color: deduct ? Colors.red.shade400 : Colors.green.shade500,
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
                style: TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(120)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWithdrawalCard(ColorScheme cs, NumberFormat nf) {
    final now = DateTime.now();
    final isFriday = now.weekday == DateTime.friday;
    final nfNoDecimal = NumberFormat('#,###', 'en');
    const minWithdraw = 5000;
    const payoutFee = 2000;

    return StreamBuilder<double>(
      stream: _service.streamSellerBalance(),
      builder: (context, snap) {
        final balance = snap.data ?? 0;
        final canWithdraw = isFriday && balance >= minWithdraw;
        final netAfterFee = balance > payoutFee ? balance - payoutFee : 0;

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isFriday
                ? Colors.green.shade50
                : cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isFriday ? Colors.green.shade200 : cs.outlineVariant,
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
                      color: isFriday
                          ? Colors.green.shade100
                          : Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isFriday ? Icons.check_circle : Icons.lock_clock,
                      color: isFriday ? Colors.green.shade700 : Colors.orange.shade700,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isFriday ? 'Payout Available' : 'Payout Locked',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: isFriday ? Colors.green.shade800 : Colors.orange.shade800,
                        ),
                      ),
                      Text(
                        isFriday
                            ? 'Ijumaa — Withdraw your earnings today!'
                            : 'Next payout: ${_service.nextPayoutDate}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isFriday ? Colors.green.shade600 : Colors.orange.shade600,
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
                  labelText: 'Phone Number',
                  hintText: 'e.g. 0712345678',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.phone_android),
                  filled: true,
                  fillColor: cs.surface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Fee: TZS ${nfNoDecimal.format(payoutFee)} | You receive: TZS ${nfNoDecimal.format(netAfterFee)}',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withAlpha(150),
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
                        ? 'Processing...'
                        : isFriday
                            ? 'Withdraw Now'
                            : 'Wait until Friday',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isFriday ? Colors.green : Colors.grey,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              if (!canWithdraw && isFriday)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Minimum balance of TZS ${nfNoDecimal.format(minWithdraw)} required (net TZS ${nfNoDecimal.format(minWithdraw - payoutFee)} after TZS ${nfNoDecimal.format(payoutFee)} fee)',
                    style: TextStyle(color: Colors.red.shade400, fontSize: 12),
                  ),
                ),
              if (!canWithdraw && !isFriday)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Minimum balance: TZS ${nfNoDecimal.format(minWithdraw)} | Fee: TZS ${nfNoDecimal.format(payoutFee)}',
                    style: TextStyle(color: cs.onSurface.withAlpha(120), fontSize: 12),
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
      _showError('Please enter your phone number');
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Withdrawal successful! Money sent to your phone.'),
            backgroundColor: Colors.green.shade600,
          ),
        );
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
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
        if (txns.isEmpty) {
          return _emptyCard(context.tr('no_transactions'), cs);
        }
        return Column(
          children: txns.take(10).map((tx) => Container(
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
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.shopping_bag, color: Colors.green.shade600, size: 20),
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
                          style: TextStyle(fontSize: 12, color: cs.onSurface.withAlpha(130)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Mongike: -TZS ${nf.format(tx.mongikeFee)} | Soko Langu: -TZS ${nf.format(tx.sokoLanguCommission)}',
                          style: TextStyle(fontSize: 11, color: Colors.red.shade300),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'TZS ${nf.format(tx.sellerReceives)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.green.shade700,
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
                          ? Colors.green.shade50
                          : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      w.status == WithdrawalStatus.completed
                          ? Icons.check_circle
                          : Icons.cancel,
                      color: w.status == WithdrawalStatus.completed
                          ? Colors.green.shade600
                          : Colors.red.shade600,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TZS ${nf.format(w.netAmount)} → ${w.phone}',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          w.status == WithdrawalStatus.completed
                              ? 'Fee: TZS ${nf.format(w.fee)} | ${DateFormat('MMM dd, yyyy HH:mm').format(w.createdAt)}'
                              : 'Failed: ${w.failureReason ?? "Unknown"}',
                          style: TextStyle(
                            fontSize: 11,
                            color: w.status == WithdrawalStatus.completed
                                ? cs.onSurface.withAlpha(130)
                                : Colors.red.shade400,
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
                      color: Colors.red.shade600,
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
            style: TextStyle(color: cs.onSurface.withAlpha(120)),
          ),
        ),
      ),
    );
  }
}
