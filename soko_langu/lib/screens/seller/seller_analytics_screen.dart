import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../services/analytics_service.dart';
import '../../models/analytics_models.dart';
import '../../theme/app_colors.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/google_loading.dart';
import '../../widgets/ds/ds.dart';
import '../../main.dart';

class SellerAnalyticsScreen extends StatefulWidget {
  final String sellerId;
  const SellerAnalyticsScreen({super.key, required this.sellerId});

  @override
  State<SellerAnalyticsScreen> createState() => _SellerAnalyticsScreenState();
}

class _SellerAnalyticsScreenState extends State<SellerAnalyticsScreen> {
  final AnalyticsService _analytics = AnalyticsService();
  SellerAnalytics? _data;
  bool _loading = true;
  Timer? _refreshTimer;
  String? _aiInsights;
  bool _aiLoading = false;
  bool _aiRequested = false;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final uid = widget.sellerId.isNotEmpty
          ? widget.sellerId
          : FirebaseAuth.instance.currentUser?.uid ?? '';
      if (uid.isEmpty) return;
      final data = await _analytics.getSellerAnalytics(uid);
      if (mounted)
        setState(() {
          _data = data;
          _loading = false;
        });
      if (!_aiRequested && data.totalProducts > 0) {
        _aiRequested = true;
        await _generateInsights();
      }
    } catch (_) {
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  Future<void> _generateInsights() async {
    final data = _data;
    if (data == null) return;
    final locale = AppConfig.of(context).langCode;
    setState(() => _aiLoading = true);
    final insights = await _analytics.generateInsights(data, locale: locale);
    if (!mounted) return;
    setState(() {
      _aiInsights = insights;
      _aiLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final nf = NumberFormat('#,###', 'en');

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(context.tr('analytics')),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: GoogleLoading())
          : _data == null
          ? Center(
              child: Text(
                context.tr('no_data'),
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  _buildSummaryRow(cs, nf),
                  const SizedBox(height: 16),
                  _buildAiInsightsCard(cs),
                  const SizedBox(height: 16),
                  _buildMonthlySalesChart(cs, nf),
                  const SizedBox(height: 16),
                  _buildOrdersCard(cs, nf),
                  const SizedBox(height: 16),
                  _buildRatingCard(cs, nf),
                  const SizedBox(height: 16),
                  _buildTopProductsCard(cs, nf),
                  const SizedBox(height: 16),
                  _buildDemographicsCard(cs),
                  const SizedBox(height: 16),
                  _buildBoostsCard(cs, nf),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(ColorScheme cs, IconData icon, String title, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: cs.onSurface),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(ColorScheme cs, NumberFormat nf) {
    final items = [
      (context.tr('products'), '${_data!.totalProducts}', Icons.inventory_2_outlined, cs.primary),
      (context.tr('views'), '${_data!.totalProductViews}', Icons.visibility_outlined, cs.secondary),
      (context.tr('sales'), '${_data!.successfulOrders}', Icons.shopping_bag_outlined, cs.successGreen),
      (context.tr('earnings'), '${context.currencySymbol()} ${_formatAmount(_data!.monthlyEarnings)}', Icons.monetization_on_outlined, cs.trendingOrange),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.6,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        return DsCard(
          radius: 20,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: item.$4.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(item.$3, color: item.$4, size: 18),
              ),
              const SizedBox(height: 8),
              Text(
                item.$2,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: cs.onSurface),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(item.$1, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAiInsightsCard(ColorScheme cs) {
    final hasData = _data!.totalProducts > 0;
    return DsCard(
      radius: 20,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildSectionHeader(cs, Icons.auto_awesome_rounded, context.tr('ai_insights'), cs.premiumAmber),
              ),
              if (_aiInsights != null)
                TextButton.icon(
                  onPressed: _aiLoading ? null : _generateInsights,
                  icon: Icon(Icons.refresh_rounded, size: 16),
                  label: Text(context.tr('regenerate'), style: const TextStyle(fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (!hasData)
            Text(
              context.tr('no_data'),
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            )
          else if (_aiLoading && _aiInsights == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: GoogleLoading()),
            )
          else if (_aiInsights == null)
            Text(
              context.tr('ai_insights_empty'),
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            )
          else
            Text(
              _aiInsights!,
              style: TextStyle(fontSize: 13, height: 1.6, color: cs.onSurface.withValues(alpha: 0.9)),
            ),
        ],
      ),
    );
  }

  Widget _buildMonthlySalesChart(ColorScheme cs, NumberFormat nf) {
    const months = ['Jan', 'Feb', 'Mac', 'Apr', 'Mei', 'Jun', 'Jul', 'Ago', 'Sep', 'Okt', 'Nov', 'Des'];
    final maxSales = _data!.monthlySales.isEmpty
        ? 1.0
        : _data!.monthlySales.map((m) => m.count.toDouble()).reduce((a, b) => a > b ? a : b);

    return DsCard(
      radius: 20,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(cs, Icons.trending_up_rounded, context.tr('monthly_sales'), cs.primary),
          const SizedBox(height: 20),
          SizedBox(
            height: 160,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(12, (i) {
                final sales = _data!.monthlySales.length > i
                    ? _data!.monthlySales[i].count.toDouble()
                    : 0.0;
                final value = maxSales > 0 ? sales / maxSales : 0.0;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '${sales.toInt()}',
                          style: TextStyle(fontSize: 8, color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          height: 120 * value.clamp(0.03, 1.0),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [cs.primary.withValues(alpha: 0.6), cs.primary.withValues(alpha: 0.25)],
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(months[i], style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersCard(ColorScheme cs, NumberFormat nf) {
    final rate = _data!.orderSuccessRate;
    return DsCard(
      radius: 20,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(cs, Icons.receipt_long_outlined, context.tr('transactions'), cs.primary),
          const SizedBox(height: 16),
          Row(
            children: [
              _statPill(cs, '${_data!.totalOrders}', context.tr('total'), cs.onSurface),
              const SizedBox(width: 8),
              _statPill(cs, '${_data!.successfulOrders}', context.tr('successful'), cs.successGreen),
              const SizedBox(width: 8),
              _statPill(cs, '${_data!.failedOrders}', context.tr('failed'), cs.error),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(context.tr('success_rate'), style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
              const Spacer(),
              Text(
                '${rate.toStringAsFixed(1)}%',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: rate > 70 ? cs.successGreen : cs.error),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: rate / 100,
              minHeight: 6,
              backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.3),
              color: rate > 70 ? cs.successGreen : cs.error,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statPill(ColorScheme cs, String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: color)),
            Text(label, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _buildRatingCard(ColorScheme cs, NumberFormat nf) {
    return DsCard(
      radius: 20,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(cs, Icons.star_rounded, context.tr('rating'), Colors.amber),
          const SizedBox(height: 16),
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _data!.averageRating.toStringAsFixed(1),
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 36, color: cs.onSurface),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('/ 5.0', style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: List.generate(5, (i) {
                      final filled = i < _data!.averageRating.round();
                      return Icon(filled ? Icons.star : Icons.star_border, color: Colors.amber, size: 18);
                    }),
                  ),
                ],
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${_data!.totalReviews}',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 24, color: cs.onSurface),
                  ),
                  Text(context.tr('total_reviews'), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Text(
                    '${_data!.positiveReviews} +',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: cs.successGreen),
                  ),
                  Text(
                    '${_data!.negativeReviews} -',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: cs.error),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopProductsCard(ColorScheme cs, NumberFormat nf) {
    return DsCard(
      radius: 20,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(cs, Icons.workspace_premium_rounded, context.tr('popular_products'), cs.premiumTeal),
          const SizedBox(height: 16),
          ..._data!.topProducts.take(5).toList().asMap().entries.map((entry) {
            final i = entry.key;
            final tp = entry.value;
            final topLoc = tp.locationBreakdown.entries.isEmpty
                ? ''
                : tp.locationBreakdown.entries
                    .reduce((a, b) => a.value > b.value ? a : b)
                    .key;
            return Padding(
              padding: EdgeInsets.only(bottom: i < 4 ? 12 : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: i == 0
                              ? cs.premiumAmber.withValues(alpha: 0.15)
                              : cs.surfaceContainerHighest.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: i == 0 ? cs.premiumAmber : cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          tp.productName,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: cs.onSurface),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text('${tp.viewCount}', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                      const SizedBox(width: 4),
                      Icon(Icons.visibility_outlined, size: 14, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                    ],
                  ),
                  if (topLoc.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 38, top: 2),
                      child: Text(
                        '${context.tr('location')}: $topLoc',
                        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildDemographicsCard(ColorScheme cs) {
    return DsCard(
      radius: 20,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(cs, Icons.people_rounded, context.tr('customers'), cs.primary),
          const SizedBox(height: 16),
          _demographicBar(cs, context.tr('male'), _data!.genderBreakdown['male'] ?? 0, cs.primary),
          const SizedBox(height: 8),
          _demographicBar(cs, context.tr('female'), _data!.genderBreakdown['female'] ?? 0, Colors.pink),
          const SizedBox(height: 12),
          if (_data!.locationBreakdown.isNotEmpty) ...[
            Text(
              '${context.tr('location')}: ${_data!.topLocation}',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface),
            ),
            const SizedBox(height: 4),
          ],
          if (_data!.ageBreakdown.isNotEmpty)
            Text(
              '${context.tr('age')}: ${_data!.topAgeGroup}',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface),
            ),
        ],
      ),
    );
  }

  Widget _demographicBar(ColorScheme cs, String label, int count, Color color) {
    final total = (_data!.genderBreakdown['male'] ?? 0) + (_data!.genderBreakdown['female'] ?? 0);
    final pct = total > 0 ? count / total : 0.0;
    if (total == 0) return const SizedBox.shrink();
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(label, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.3),
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 40,
          child: Text(
            '${(pct * 100).toStringAsFixed(0)}%',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildBoostsCard(ColorScheme cs, NumberFormat nf) {
    return DsCard(
      radius: 20,
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.boostGold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.rocket_launch_rounded, color: cs.boostGold, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('boosts'),
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_data!.boostImpressions} ${context.tr('impressions')}',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (_data!.boostLocationBreakdown.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: cs.boostGold.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _data!.boostLocationBreakdown.entries
                    .reduce((a, b) => a.value > b.value ? a : b)
                    .key,
                style: TextStyle(fontSize: 11, color: cs.boostGold),
              ),
            ),
        ],
      ),
    );
  }

  String _formatAmount(double amount) {
    final nf = NumberFormat('#,###', 'en');
    if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(1)}M';
    }
    if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(1)}K';
    }
    return nf.format(amount);
  }
}
