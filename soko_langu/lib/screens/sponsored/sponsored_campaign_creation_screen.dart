import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../models/product_model.dart';
import '../../models/sponsored_campaign.dart';
import '../../services/sponsored_service.dart';
import '../../services/product_service.dart';
import '../../app/routes.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/product_cached_image.dart';

class SponsoredCampaignCreationScreen extends StatefulWidget {
  final String productId;
  final Product? product;

  const SponsoredCampaignCreationScreen({super.key, this.productId = '', this.product});

  @override
  State<SponsoredCampaignCreationScreen> createState() => _SponsoredCampaignCreationScreenState();
}

class _SponsoredCampaignCreationScreenState extends State<SponsoredCampaignCreationScreen> {
  final NumberFormat _nf = NumberFormat('#,##0', 'en_US');
  final TextEditingController _customDailyCtrl = TextEditingController();
  final SponsoredService _service = SponsoredService();
  final ProductService _productService = ProductService();

  int _currentStep = 0;
  List<BudgetTier> _budgetTiers = [];
  List<Product> _myProducts = [];
  String? _selectedProductId;
  String _objective = 'objective_increase_visibility';
  String _placement = 'search';
  int _durationDays = 7;
  int? _dailyBudgetTzs;
  bool _loading = true;
  bool _creating = false;

  static const List<({String value, String labelKey})> _placements = [
    (value: 'search', labelKey: 'placement_sponsored_search'),
    (value: 'category', labelKey: 'placement_sponsored_category'),
    (value: 'recommendations', labelKey: 'placement_sponsored_recommendations'),
    (value: 'product_feed', labelKey: 'placement_sponsored_product_feed'),
    (value: 'store_discovery', labelKey: 'placement_sponsored_store_discovery'),
    (value: 'featured', labelKey: 'placement_featured_sponsored'),
  ];

  static const List<({int days, String labelKey})> _durations = [
    (days: 1, labelKey: 'duration_1_day'),
    (days: 3, labelKey: 'duration_3_days'),
    (days: 7, labelKey: 'duration_7_days'),
    (days: 14, labelKey: 'duration_14_days'),
    (days: 30, labelKey: 'duration_30_days'),
  ];

  static const List<({String value, String labelKey, String descKey})> _objectives = [
    (
      value: 'objective_increase_visibility',
      labelKey: 'objective_increase_visibility',
      descKey: 'objective_increase_visibility_desc',
    ),
    (
      value: 'objective_reach_relevant_shoppers',
      labelKey: 'objective_reach_relevant_shoppers',
      descKey: 'objective_reach_relevant_shoppers_desc',
    ),
    (
      value: 'objective_promote_new_product',
      labelKey: 'objective_promote_new_product',
      descKey: 'objective_promote_new_product_desc',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _selectedProductId = widget.productId.isNotEmpty ? widget.productId : widget.product?.id;
    _loadTiers();
    _loadProducts();
  }

  @override
  void dispose() {
    _customDailyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTiers() async {
    try {
      final tiers = await _service.fetchBudgetTiers();
      if (mounted) setState(() => _budgetTiers = tiers);
    } catch (_) {}
  }

  Future<void> _loadProducts() async {
    try {
      final products = await _productService.getMyProducts().first;
      if (mounted) setState(() => _myProducts = products);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  bool get _lastStep => _currentStep == 4;

  bool get _stepValid {
    switch (_currentStep) {
      case 0:
        return _selectedProductId != null;
      case 4:
        return _dailyBudgetTzs != null && _dailyBudgetTzs! > 0;
      default:
        return true;
    }
  }

  void _nextStep() {
    if (!_stepValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('required')), backgroundColor: Theme.of(context).colorScheme.error),
      );
      return;
    }
    if (_lastStep) {
      _createCampaign();
      return;
    }
    setState(() => _currentStep++);
  }

  Future<void> _createCampaign() async {
    if (_selectedProductId == null || _dailyBudgetTzs == null) return;
    setState(() => _creating = true);

    final product = _selectedProduct;
    final name = 'Sponsored: ${product?.name ?? 'Campaign'}';
    final startsAt = DateTime.now().add(const Duration(minutes: 1));
    final expiresAt = startsAt.add(Duration(days: _durationDays));

    try {
      final campaign = await _service.createCampaign(
        name: name,
        dailyBudgetTzs: _dailyBudgetTzs!,
        totalBudgetTzs: _dailyBudgetTzs! * _durationDays,
        bidAmountTzs: (_dailyBudgetTzs! ~/ 10).clamp(1, 1 << 31),
        placement: _placement,
        startsAt: startsAt,
        expiresAt: expiresAt,
        productIds: [_selectedProductId!],
        isAllProducts: false,
      );
      if (!mounted) return;
      setState(() => _creating = false);
      _navigateToPayment(campaign);
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create campaign: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _navigateToPayment(SponsoredCampaign campaign) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PaymentSheet(
        campaign: campaign,
        onPaymentInitiated: (phone, method) async {
          try {
            await _service.initiatePayment(
              campaignId: campaign.id,
              phone: phone,
              paymentMethod: method,
            );
            if (mounted) {
              context.push(AppRoutes.sponsoredDashboard);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.tr('payment_initiated')), backgroundColor: Colors.green),
              );
            }
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Payment failed: $e'), backgroundColor: Colors.red),
            );
          }
        },
      ),
    );
  }

  Product? get _selectedProduct {
    if (_selectedProductId == null) return null;
    for (final p in _myProducts) {
      if (p.id == _selectedProductId) return p;
    }
    return null;
  }

  int get _totalBudgetTzs {
    final daily = _dailyBudgetTzs ?? 0;
    return daily * _durationDays;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(context.tr('create_sponsored_campaign')),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).brightness == Brightness.dark ? Colors.black : Colors.white,
              cs.surface,
            ],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    _buildStepIndicator(cs),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: _buildStepContent(cs),
                      ),
                    ),
                    _buildNavBar(cs),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: List.generate(5, (i) {
          final active = i <= _currentStep;
          final current = i == _currentStep;
          return Expanded(
            child: current
                ? AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  )
                : AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: active ? cs.primary.withValues(alpha: 0.4) : cs.outlineVariant,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
          );
        }),
      ),
    );
  }

  Widget _buildStepContent(ColorScheme cs) {
    switch (_currentStep) {
      case 0:
        return _buildSelectProduct(cs);
      case 1:
        return _buildObjective(cs);
      case 2:
        return _buildPlacement(cs);
      case 3:
        return _buildDuration(cs);
      default:
        return _buildBudget(cs);
    }
  }

  Widget _buildSectionHeader(String titleKey, String descKey) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr(titleKey), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(context.tr(descKey), style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSelectProduct(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('campaign_creation_step1_title', 'campaign_creation_step1_desc'),
        if (_myProducts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text(context.tr('no_products_available'))),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _myProducts.length,
            itemBuilder: (context, i) => _buildProductCard(cs, _myProducts[i]),
          ),
      ],
    );
  }

  Widget _buildProductCard(ColorScheme cs, Product p) {
    final isSelected = p.id == _selectedProductId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _selectedProductId = p.id),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected ? cs.primary.withValues(alpha: 0.08) : cs.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? cs.primary : cs.outlineVariant.withValues(alpha: 0.4),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 64,
                  height: 64,
                  color: cs.surfaceContainerLow,
                  child: p.images.isNotEmpty
                      ? ProductCachedImage(url: p.images.first, fit: BoxFit.cover)
                      : Icon(Icons.image, color: cs.onSurfaceVariant, size: 28),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text('${p.currency ?? 'TSh'} ${_nf.format(p.price.round())}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.primary)),
                    const SizedBox(height: 4),
                    Text(p.category, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        _buildMetricChip(cs, Icons.visibility_outlined, '${p.viewCount} ${context.tr('views')}'),
                        _buildMetricChip(cs, Icons.shopping_bag_outlined, '${p.soldCount} ${context.tr('sales')}'),
                        _buildMetricChip(cs, Icons.inventory_2_outlined, '${p.stock} ${context.tr('stock')}'),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: isSelected ? cs.primary : cs.outlineVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricChip(ColorScheme cs, IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: cs.onSurfaceVariant),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ],
    );
  }

  Widget _buildObjective(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('campaign_creation_step2_title', 'campaign_creation_step2_desc'),
        ..._objectives.map((o) => _buildRadioCard(
              cs,
              value: o.value,
              selected: _objective == o.value,
              title: context.tr(o.labelKey),
              description: context.tr(o.descKey),
              icon: Icons.track_changes_outlined,
              onTap: () => setState(() => _objective = o.value),
            )),
      ],
    );
  }

  Widget _buildPlacement(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('campaign_creation_step3_title', 'campaign_creation_step3_desc'),
        ..._placements.map((p) => _buildRadioCard(
              cs,
              value: p.value,
              selected: _placement == p.value,
              title: context.tr(p.labelKey),
              icon: Icons.ads_click_outlined,
              onTap: () => setState(() => _placement = p.value),
            )),
      ],
    );
  }

  Widget _buildDuration(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('campaign_creation_step4_title', 'campaign_creation_step4_desc'),
        ..._durations.map(
          (d) => _buildRadioCard(
            cs,
            value: d.days.toString(),
            selected: _durationDays == d.days,
            title: context.tr(d.labelKey),
            icon: Icons.schedule_outlined,
            onTap: () => setState(() => _durationDays = d.days),
          ),
        ),
      ],
    );
  }

  Widget _buildBudget(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('campaign_creation_step5_title', 'campaign_creation_step5_desc'),
        Text(context.tr('choose_budget_amount'), style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        const SizedBox(height: 8),
        if (_budgetTiers.isNotEmpty)
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ..._budgetTiers.map(_buildTierCard(cs)),
              _buildCustomBudgetCard(cs),
            ],
          ),
        const SizedBox(height: 12),
        Text(context.tr('you_control_campaign_budget'), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        const SizedBox(height: 24),
        _buildCampaignSummary(cs),
      ],
    );
  }

  Widget Function(BudgetTier tier) _buildTierCard(ColorScheme cs) {
    return (tier) {
      final daily = tier.dailyBudget;
      final isSelected = _dailyBudgetTzs == daily;
      return GestureDetector(
        onTap: () {
          setState(() {
            _dailyBudgetTzs = daily;
            _customDailyCtrl.clear();
          });
        },
        child: Container(
          width: 150,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected ? cs.primary.withValues(alpha: 0.08) : cs.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSelected ? cs.primary : cs.outlineVariant.withValues(alpha: 0.4), width: isSelected ? 2 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.tr('budget_tier_${tier.name.toLowerCase()}'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('TZS ${_nf.format(daily)}/day', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      );
    };
  }

  Widget _buildCustomBudgetCard(ColorScheme cs) {
    final isCustom = _customDailyCtrl.text.isNotEmpty;
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCustom ? cs.primary.withValues(alpha: 0.08) : cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isCustom ? cs.primary : cs.outlineVariant.withValues(alpha: 0.4), width: isCustom ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('custom_budget_label'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          TextField(
            controller: _customDailyCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: 'TZS / ${context.tr('days_abbr')}',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onChanged: (v) {
              final parsed = int.tryParse(v);
              setState(() => _dailyBudgetTzs = (parsed != null && parsed > 0) ? parsed : null);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRadioCard(
    ColorScheme cs, {
    required String value,
    required bool selected,
    required String title,
    String? description,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? cs.primary.withValues(alpha: 0.08) : cs.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? cs.primary : cs.outlineVariant.withValues(alpha: 0.4),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: selected ? cs.primary : cs.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr(title), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    if (description != null) ...[
                      const SizedBox(height: 2),
                      Text(context.tr(description), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected ? cs.primary : cs.outlineVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCampaignSummary(ColorScheme cs) {
    final product = _selectedProduct;
    final objective = _objectives.firstWhere((o) => o.value == _objective).labelKey;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('campaign_summary_title'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface)),
          const SizedBox(height: 12),
          _summaryRow(cs, context.tr('campaign_summary_product'), product?.name ?? '—'),
          _summaryRow(cs, context.tr('campaign_summary_objective'), context.tr(objective)),
          _summaryRow(cs, context.tr('campaign_summary_placements'), context.tr(_placements.firstWhere((p) => p.value == _placement).labelKey)),
          _summaryRow(cs, context.tr('campaign_summary_duration'), '$_durationDays ${context.tr('days')}'),
          _summaryRow(
            cs,
            context.tr('campaign_summary_budget'),
            'TZS ${_nf.format(_totalBudgetTzs)}  (${_nf.format(_dailyBudgetTzs ?? 0)}/day)',
            highlight: true,
          ),
          const SizedBox(height: 12),
          Text(context.tr('campaign_summary_note'), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _summaryRow(ColorScheme cs, String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text(label, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant))),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
                color: highlight ? cs.primary : cs.onSurface,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavBar(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: _creating ? null : () => setState(() => _currentStep--),
                child: Text(context.tr('go_back')),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: _creating ? null : _nextStep,
              child: _creating
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_lastStep ? context.tr('start_sponsored_campaign_cta') : context.tr('next')),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentSheet extends StatelessWidget {
  final SponsoredCampaign campaign;
  final Function(String phone, String method) onPaymentInitiated;

  const _PaymentSheet({required this.campaign, required this.onPaymentInitiated});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final nf = NumberFormat('#,###', 'en');
    final phoneCtrl = TextEditingController();
    String selectedMethod = 'ussd_push';

    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 24, left: 24, right: 24, top: 24),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('payment_method'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.onSurface)),
          const SizedBox(height: 16),
          Text('TZS ${nf.format(campaign.totalBudgetTzs.toInt())}', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: cs.primary)),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: selectedMethod,
            items: [
              DropdownMenuItem(value: 'ussd_push', child: Text(context.tr('ussd_push_method'))),
              DropdownMenuItem(value: 'billpay', child: Text(context.tr('billpay_method'))),
            ],
            onChanged: (v) => selectedMethod = v ?? 'ussd_push',
            decoration: InputDecoration(labelText: context.tr('payment_method'), border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: phoneCtrl,
            decoration: InputDecoration(labelText: context.tr('phone_number'), border: const OutlineInputBorder()),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () {
              if (phoneCtrl.text.trim().isEmpty) return;
              Navigator.pop(context);
              onPaymentInitiated(phoneCtrl.text.trim(), selectedMethod);
            },
            child: Text(context.tr('pay_and_activate')),
          ),
        ],
      ),
    );
  }
}