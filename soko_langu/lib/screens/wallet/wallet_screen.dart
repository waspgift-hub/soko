import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../services/api_config.dart';
import '../../services/balance_privacy_service.dart';
import '../../extensions/context_tr.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  double _balance = 0;
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;
  List<Map<String, dynamic>> _methods = [];
  bool _methodsLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final balResp = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/wallet/balance/${user.uid}'),
      );
      if (balResp.statusCode == 200) {
        final data = jsonDecode(balResp.body) as Map<String, dynamic>;
        _balance = (data['balance'] as num?)?.toDouble() ?? 0;
      }
      final histResp = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/wallet/history/${user.uid}'),
      );
      if (histResp.statusCode == 200) {
        final data = jsonDecode(histResp.body) as Map<String, dynamic>;
        _history = (data['history'] as List?)
                ?.map((e) => e as Map<String, dynamic>)
                .toList() ??
            [];
      }
    } catch (_) {}
    _loadMethods();
    setState(() => _loading = false);
  }

  Future<void> _loadMethods() async {
    setState(() => _methodsLoading = true);
    try {
      final resp = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/wallet/deposit/methods'),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        _methods = (data['methods'] as List?)
                ?.map((e) => e as Map<String, dynamic>)
                .toList() ??
            [];
      }
    } catch (_) {}
    setState(() => _methodsLoading = false);
  }

  void _showMethodSelector() {
    final tr = context.tr;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              tr('select_method'),
              style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            if (_methodsLoading)
              const Center(child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ))
            else
              ..._methods.map((m) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _MethodCard(
                  method: m,
                  onTap: () {
                    Navigator.pop(ctx);
                    _startDeposit(m);
                  },
                ),
              )),
          ],
        ),
      ),
    );
  }

  void _startDeposit(Map<String, dynamic> method) {
    _showUssdDepositDialog();
  }

  void _showUssdDepositDialog() {
    final amtCtrl = TextEditingController();
    final phoneCtrl = TextEditingController(text: '255');
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('deposit_method_ussd')),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: amtCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.tr('amount'),
                  border: const OutlineInputBorder(),
                  prefixText: 'TZS ',
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  final n = int.tryParse(v);
                  if (n == null || n < 1000) return 'Minimum TZS 1,000';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: context.tr('phone'),
                  border: const OutlineInputBorder(),
                  hintText: '2557XXXXXXXX',
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (!v.startsWith('255')) return 'Must start with 255';
                  if (v.length < 10) return 'Too short';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: Text(context.tr('deposit')),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) {
        final amount = int.parse(amtCtrl.text);
        final phone = phoneCtrl.text;
        _depositUssd(amount, phone);
      }
    });
  }

  Future<void> _depositUssd(int amount, String phone) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _loading = true);

    try {
      final token = await user.getIdToken();
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/wallet/deposit'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'userId': user.uid,
          'phone': phone,
          'amount': amount,
          'method': 'ussd',
        }),
      );
      final data = jsonDecode(resp.body) as Map<String, dynamic>;

      if (!mounted) return;

      if (resp.statusCode == 200 && data['success'] == true) {
        final depositRef = data['depositRef'] as String;
        _showUssdWaitingSheet(depositRef);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['error'] ?? 'Deposit failed'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _showLipaWaitingSheet(String depositRef, String tillNumber, int amount) async {
    final tr = context.tr;
    final completer = Completer<void>();
    StreamSubscription<DocumentSnapshot>? sub;

    await showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && sub != null) sub!.cancel();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('deposits')
                  .doc(depositRef)
                  .snapshots(),
              builder: (ctx, snap) {
                final status = snap.data?.get('status') as String? ?? 'pending';

                // Cancel stream & close when done
                if (status == 'completed' || status == 'failed') {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (ctx.mounted && !completer.isCompleted) {
                      completer.complete();
                      Navigator.of(ctx).pop();
                    }
                  });
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (status == 'completed')
                      const Icon(Icons.check_circle, color: Colors.green, size: 64)
                    else if (status == 'failed')
                      const Icon(Icons.cancel, color: Colors.red, size: 64)
                    else
                      const SizedBox(
                        width: 64, height: 64,
                        child: CircularProgressIndicator(strokeWidth: 4),
                      ),
                    const SizedBox(height: 20),
                    Text(
                      status == 'completed'
                          ? tr('lipa_success')
                          : status == 'failed'
                              ? 'Deposit failed'
                              : tr('lipa_pending'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    if (status != 'completed' && status != 'failed')
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          tr('lipa_waiting_desc'),
                          style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.6)),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    const SizedBox(height: 20),
                    // Till ref display
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Text(tr('till_number'),
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.5))),
                          const SizedBox(height: 4),
                          Text(tillNumber,
                              style: const TextStyle(
                                  fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 3)),
                          const SizedBox(height: 8),
                          Text('TZS $amount',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (status == 'completed' || status == 'failed')
                      FilledButton(
                        onPressed: () {
                          if (!completer.isCompleted) {
                            completer.complete();
                          }
                          Navigator.of(ctx).pop();
                        },
                        child: Text(status == 'completed' ? tr('continue') : tr('retry')),
                      ),
                    if (status == 'pending')
                      TextButton(
                        onPressed: () {
                          if (!completer.isCompleted) {
                            completer.complete();
                          }
                          Navigator.of(ctx).pop();
                        },
                        child: Text(tr('cancel')),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    if (!completer.isCompleted) {
      completer.complete();
      sub?.cancel();
    }
    _load();
  }

  Future<void> _showUssdWaitingSheet(String depositRef) async {
    final tr = context.tr;
    final completer = Completer<void>();
    StreamSubscription<DocumentSnapshot>? sub;

    await showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && sub != null) sub!.cancel();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('deposits')
                  .doc(depositRef)
                  .snapshots(),
              builder: (ctx, snap) {
                final status = snap.data?.get('status') as String? ?? 'pending';

                if (status == 'completed' || status == 'failed') {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (ctx.mounted && !completer.isCompleted) {
                      completer.complete();
                      Navigator.of(ctx).pop();
                    }
                  });
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (status == 'completed')
                      const Icon(Icons.check_circle, color: Colors.green, size: 64)
                    else if (status == 'failed')
                      const Icon(Icons.cancel, color: Colors.red, size: 64)
                    else
                      const SizedBox(
                        width: 64, height: 64,
                        child: CircularProgressIndicator(strokeWidth: 4),
                      ),
                    const SizedBox(height: 20),
                    Text(
                      status == 'completed'
                          ? 'Deposit successful'
                          : status == 'failed'
                              ? 'Deposit failed'
                              : 'Waiting for payment...',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    if (status == 'pending')
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'Complete payment on your phone via USSD push',
                          style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.6)),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    const SizedBox(height: 24),
                    if (status == 'completed' || status == 'failed')
                      FilledButton(
                        onPressed: () {
                          if (!completer.isCompleted) {
                            completer.complete();
                          }
                          Navigator.of(ctx).pop();
                        },
                        child: Text(status == 'completed' ? tr('continue') : tr('retry')),
                      ),
                    if (status == 'pending')
                      TextButton(
                        onPressed: () {
                          if (!completer.isCompleted) {
                            completer.complete();
                          }
                          Navigator.of(ctx).pop();
                        },
                        child: Text(tr('cancel')),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    if (!completer.isCompleted) {
      completer.complete();
      sub?.cancel();
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tr = context.tr;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('wallet')),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Consumer<BalancePrivacyService>(
                    builder: (ctx, privacy, _) => _BalanceCard(
                      balance: _balance,
                      tr: tr,
                      cs: cs,
                      hideBalance: privacy.hideBalances,
                      onToggleEye: privacy.toggle,
                      onDeposit: _showMethodSelector,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Icon(Icons.add_circle_outline, color: cs.onSurface.withValues(alpha: 0.6), size: 20),
                      const SizedBox(width: 8),
                      Text(
                        tr('deposit_methods'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_methodsLoading)
                    const Center(child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ))
                  else
                    ..._methods.map((m) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _MethodCard(method: m, onTap: () => _startDeposit(m)),
                    )),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.history, color: cs.onSurface.withValues(alpha: 0.6), size: 20),
                      const SizedBox(width: 8),
                      Text(
                        tr('transaction_history'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_history.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(40),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.account_balance_wallet_outlined,
                                size: 48, color: cs.onSurface.withValues(alpha: 0.2)),
                            const SizedBox(height: 12),
                            Text(
                              tr('no_transactions'),
                              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.4)),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._history.map((tx) => _buildTxCard(tx, cs)),
                ],
              ),
      ),
    );
  }

  Widget _buildTxCard(Map<String, dynamic> tx, ColorScheme cs) {
    final status = tx['status'] as String? ?? '';
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
    final pm = tx['paymentMethod'] as String? ?? '';
    final isCompleted = status == 'completed';
    final isFailed = status == 'failed';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(
          isCompleted
              ? Icons.check_circle
              : isFailed
                  ? Icons.cancel
                  : Icons.hourglass_top,
          color: isCompleted
              ? Colors.green
              : isFailed
                  ? Colors.red
                  : Colors.orange,
        ),
        title: Text(
          isCompleted
              ? 'Deposit Completed'
              : isFailed
                  ? 'Deposit Failed'
                  : 'Processing...',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text('TZS ${amount.toStringAsFixed(0)}  ·  $pm'),
        trailing: Text(
          status.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isCompleted
                ? Colors.green
                : isFailed
                    ? Colors.red
                    : Colors.orange,
          ),
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final double balance;
  final String Function(String) tr;
  final ColorScheme cs;
  final bool hideBalance;
  final VoidCallback onToggleEye;
  final VoidCallback onDeposit;

  const _BalanceCard({
    required this.balance,
    required this.tr,
    required this.cs,
    required this.hideBalance,
    required this.onToggleEye,
    required this.onDeposit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [cs.primary, cs.primary.withValues(alpha: 0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                tr('wallet_balance'),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onToggleEye,
                child: Icon(
                  hideBalance ? Icons.visibility_off : Icons.visibility,
                  color: Colors.white.withValues(alpha: 0.7),
                  size: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            hideBalance ? 'TZS ****' : 'TZS ${balance.toStringAsFixed(0)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 42,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onDeposit,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: cs.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.add_circle_outline),
              label: Text(
                tr('deposit'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  final Map<String, dynamic> method;
  final VoidCallback onTap;

  const _MethodCard({required this.method, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final id = method['id'] as String? ?? '';
    final name = method['name'] as String? ?? '';
    final description = method['description'] as String? ?? '';
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.swap_vert,
                  color: cs.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(description,
                        style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurface.withValues(alpha: 0.55))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cs.onSurface.withValues(alpha: 0.3)),
            ],
          ),
        ),
      ),
    );
  }
}
