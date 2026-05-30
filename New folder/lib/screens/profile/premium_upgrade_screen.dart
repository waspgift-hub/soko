import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/user_service.dart';
import '../../services/mongike_service.dart';
import '../../extensions/context_tr.dart';
import '../../main.dart';

class _ComparisonRow {
  final String feature;
  final bool free;
  final bool silver;
  final bool premium;
  final String? freeLabel;
  final String? silverLabel;
  final String? premiumLabel;

  _ComparisonRow({
    required this.feature,
    required this.free,
    required this.silver,
    required this.premium,
    this.freeLabel,
    this.silverLabel,
    this.premiumLabel,
  });
}

class PremiumUpgradeScreen extends StatefulWidget {
  final String? initialTier;

  const PremiumUpgradeScreen({super.key, this.initialTier});

  @override
  State<PremiumUpgradeScreen> createState() => _PremiumUpgradeScreenState();
}

class _PremiumUpgradeScreenState extends State<PremiumUpgradeScreen> {
  late String _selectedTier;
  bool _isYearly = true;
  bool _isLoading = false;
  bool _isSuccess = false;
  String? _error;
  final _phoneController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialTier == 'premium' || widget.initialTier == 'silver') {
      _selectedTier = widget.initialTier!;
    } else {
      _selectedTier = 'premium';
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  double get _amount {
    if (_selectedTier == 'silver') return _isYearly ? 100000 : 10000;
    return _isYearly ? 250000 : 25000;
  }

  String get _tierLabel {
    if (_selectedTier == 'silver') return 'Silver';
    return 'Premium';
  }

  Future<void> _subscribe() async {
    if (_phoneController.text.trim().isEmpty) {
      setState(() {
        _error = 'Enter your phone number';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final result = await MongikeService.initiatePayment(
      tier: _selectedTier,
      isYearly: _isYearly,
      email: user.email ?? '',
      phone: _phoneController.text.trim(),
      userId: user.uid,
    );

    if (result == null || result['order_id'] == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = context.tr('failed_payment_init');
      });
      return;
    }

    if (!mounted) return;
    _showProcessingDialog(result['order_id'], user.uid);
  }

  void _showProcessingDialog(String orderId, String uid) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('transactions')
              .doc(orderId)
              .snapshots(),
          builder: (ctx, snap) {
            final status = snap.data?.get('status') as String?;

            if (status == 'completed') {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _onPaymentSuccess(uid);
              });
              return AlertDialog(
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 64,
                    ),
                    const SizedBox(height: 16),
                    Text(context.tr('payment_confirmed_activating')),
                  ],
                ),
              );
            }

            return AlertDialog(
              title: Text(context.tr('complete_payment')),
              content: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Payment prompt sent to your phone.\n'
                    'Check M-Pesa, Airtel Money, or Mixx\n'
                    'and enter your PIN to complete payment.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() => _isLoading = false);
                  },
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _onPaymentSuccess(String uid) async {
    final duration = _isYearly
        ? const Duration(days: 365)
        : const Duration(days: 30);
    await UserService().setAccountTier(
      uid,
      _selectedTier,
      subscriptionDuration: duration,
    );
    await UserService().setVerified(uid, true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('account_tier', _selectedTier);
    if (mounted) {
      AppConfig.of(context).onSetTier(_selectedTier);
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('upgrade_account'))),
      body: SafeArea(child: _isSuccess ? _buildSuccess() : _buildUpgrade()),
    );
  }

  Widget _buildSuccess() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _selectedTier == 'silver'
                    ? Icons.workspace_premium
                    : Icons.verified,
                color: _selectedTier == 'silver'
                    ? Colors.blueGrey
                    : Colors.amber,
                size: 96,
              ),
              const SizedBox(height: 24),
              Text(
                '${context.tr('welcome_premium')} $_tierLabel!',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                _selectedTier == 'silver'
                    ? context.tr('silver_welcome_msg')
                    : context.tr('premium_no_ads'),
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.6),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _selectedTier == 'silver'
                      ? Colors.blueGrey
                      : Colors.amber,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 48,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  '$_tierLabel ${context.tr('premium_active')}',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUpgrade() {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 20,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 16),
            _buildTierSelector(),
            const SizedBox(height: 20),
            _buildPricingToggle(),
            const SizedBox(height: 20),
            _buildFeatureComparison(),
            const SizedBox(height: 20),
            _buildPhoneField(),
            const SizedBox(height: 16),
            _buildSubscribeButton(),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 14),
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildTierSelector() {
    return Row(
      children: [
        Expanded(
          child: _tierCard(
            tier: 'silver',
            price: _isYearly ? 'TZS 100,000' : 'TZS 10,000',
            period: _isYearly
                ? context.tr('per_year')
                : context.tr('per_month'),
            isSelected: _selectedTier == 'silver',
            onTap: () => setState(() => _selectedTier = 'silver'),
            icon: Icons.workspace_premium,
            color: Colors.blueGrey,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _tierCard(
            tier: 'premium',
            price: _isYearly ? 'TZS 250,000' : 'TZS 25,000',
            period: _isYearly
                ? context.tr('per_year')
                : context.tr('per_month'),
            isSelected: _selectedTier == 'premium',
            onTap: () => setState(() => _selectedTier = 'premium'),
            icon: Icons.verified,
            color: Colors.amber,
          ),
        ),
      ],
    );
  }

  Widget _tierCard({
    required String tier,
    required String price,
    required String period,
    required bool isSelected,
    required VoidCallback onTap,
    required IconData icon,
    required Color color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.08) : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : Theme.of(context).colorScheme.primary.withOpacity(0.5),
            width: isSelected ? 2 : 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? color : Theme.of(context).colorScheme.onSurfaceVariant, size: 36),
            const SizedBox(height: 8),
            Text(
              tier == 'silver' ? context.tr('silver') : context.tr('premium'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isSelected
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              price,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: isSelected
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            Text(
              period,
              style: TextStyle(
                fontSize: 12,
                color: isSelected
                    ? Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.6)
                    : Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPricingToggle() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: _pricingOption(
              context.tr('monthly'),
              !_isYearly,
              () => setState(() => _isYearly = false),
              null,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _pricingOption(
              context.tr('yearly'),
              _isYearly,
              () => setState(() => _isYearly = true),
              context.tr('save'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pricingOption(
    String title,
    bool selected,
    VoidCallback onTap,
    String? badge,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.surface
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: selected
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                )
              : null,
        ),
        child: Column(
          children: [
            if (badge != null)
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${context.tr('save')} ~17%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else
              const SizedBox(height: 18),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureComparison() {
    final comparison = [
      _ComparisonRow(
        feature: context.tr('free_feature_watch_ad'),
        free: false,
        silver: true,
        premium: true,
      ),
      _ComparisonRow(
        feature: context.tr('silver_feature_instant'),
        free: false,
        silver: true,
        premium: true,
      ),
      _ComparisonRow(
        feature: context.tr('silver_feature_visibility'),
        free: false,
        silver: true,
        premium: true,
      ),
      _ComparisonRow(
        feature: context.tr('premium_feature_badges'),
        free: false,
        silver: false,
        premium: true,
      ),
      _ComparisonRow(
        feature: context.tr('free_limit'),
        free: true,
        silver: true,
        premium: true,
        freeLabel: '50',
        silverLabel: '500',
        premiumLabel: context.tr('unlimited'),
      ),
      _ComparisonRow(
        feature: context.tr('silver_feature_support'),
        free: false,
        silver: true,
        premium: true,
      ),
      _ComparisonRow(
        feature: context.tr('premium_feature_featured'),
        free: false,
        silver: false,
        premium: true,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('plan_compare'),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _buildComparisonHeader(),
              const Divider(height: 1),
              ...comparison.asMap().entries.map((entry) {
                final isLast = entry.key == comparison.length - 1;
                return Column(
                  children: [
                    _buildComparisonRow(entry.value),
                    if (!isLast) const Divider(height: 1),
                  ],
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildComparisonHeader() {
    final silverColor = Colors.blueGrey;
    final premiumColor = Colors.amber;
    return Container(
      decoration: BoxDecoration(
        color: premiumColor.withOpacity(0.08),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              context.tr('plan_compare'),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                context.tr('free'),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                'Silver',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: silverColor,
                ),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                'Premium',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: premiumColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonRow(_ComparisonRow row) {
    final silverColor = Colors.blueGrey;
    final premiumColor = Colors.amber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              row.feature,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: Center(
              child: row.freeLabel != null
                  ? Text(row.freeLabel!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))
                  : Icon(
                      row.free ? Icons.check_circle : Icons.cancel,
                      size: 18,
                      color: row.free ? Colors.green : Colors.grey.shade300,
                    ),
            ),
          ),
          Expanded(
            child: Center(
              child: row.silverLabel != null
                  ? Text(row.silverLabel!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: silverColor))
                  : Icon(
                      row.silver ? Icons.check_circle : Icons.cancel,
                      size: 18,
                      color: row.silver ? silverColor : Colors.grey.shade300,
                    ),
            ),
          ),
          Expanded(
            child: Center(
              child: row.premiumLabel != null
                  ? Text(row.premiumLabel!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: premiumColor))
                  : Icon(
                      row.premium ? Icons.check_circle : Icons.cancel,
                      size: 18,
                      color: row.premium ? premiumColor : Colors.grey.shade300,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneField() {
    return TextField(
      controller: _phoneController,
      decoration: InputDecoration(
        labelText: context.tr('phone_number'),
        hintText: context.tr('phone_hint'),
        prefixIcon: const Icon(Icons.phone),
        border: const OutlineInputBorder(),
      ),
      keyboardType: TextInputType.phone,
    );
  }

  Widget _buildSubscribeButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: _selectedTier == 'silver'
              ? Colors.blueGrey
              : Colors.amber,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        onPressed: _isLoading ? null : _subscribe,
        icon: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Icon(Icons.payment, color: Colors.white, size: 20),
        label: Text(
          _isLoading
              ? context.tr('processing')
              : '${context.tr('pay_mongike')} TZS ${_amount.toStringAsFixed(0)}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

