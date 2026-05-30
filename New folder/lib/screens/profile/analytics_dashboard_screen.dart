import 'package:flutter/material.dart';
import '../../services/analytics_service.dart';
import '../../extensions/context_tr.dart';

class AnalyticsDashboardScreen extends StatefulWidget {
  const AnalyticsDashboardScreen({super.key});

  @override
  State<AnalyticsDashboardScreen> createState() => _AnalyticsDashboardScreenState();
}

class _AnalyticsDashboardScreenState extends State<AnalyticsDashboardScreen> {
  final _analyticsService = AnalyticsService();
  bool _loading = true;
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _topProducts = [];
  List<Map<String, dynamic>> _revenueByDay = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final stats = await _analyticsService.getDashboardStats();
      final topProducts = await _analyticsService.getTopProducts();
      final revenueByDay = await _analyticsService.getRevenueByDay(30);

      if (mounted) {
        setState(() {
          _stats = stats;
          _topProducts = topProducts;
          _revenueByDay = revenueByDay;
        });
      }
    } catch (e) {
      debugPrint('Analytics error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('analytics')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildOverviewCards(),
                    const SizedBox(height: 24),
                    Text(
                      context.tr('top_products'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    _buildTopProducts(),
                    const SizedBox(height: 24),
                    Text(
                      context.tr('revenue_trend'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    _buildRevenueChart(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildOverviewCards() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.4,
      children: [
        _statCard(
          Icons.shopping_bag,
          '${_stats['totalOrders'] ?? 0}',
          context.tr('total_orders'),
          Colors.blue,
        ),
        _statCard(
          Icons.monetization_on,
          'TSh ${(_stats['totalRevenue'] ?? 0).toStringAsFixed(0)}',
          context.tr('total_revenue'),
          Colors.green,
        ),
        _statCard(
          Icons.inventory_2,
          '${_stats['totalProducts'] ?? 0}',
          context.tr('total_products'),
          Colors.orange,
        ),
        _statCard(
          Icons.visibility,
          '${_stats['totalViews'] ?? 0}',
          context.tr('total_views'),
          Colors.purple,
        ),
      ],
    );
  }

  Widget _statCard(IconData icon, String value, String label, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopProducts() {
    if (_topProducts.isEmpty) {
      return Center(
        child: Text(context.tr('no_products_yet'), style: TextStyle(color: Colors.grey[500])),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _topProducts.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final product = _topProducts[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.green.shade50,
            child: Text('${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          title: Text(product['name'] ?? 'Unknown'),
          subtitle: Text('TSh ${(product['price'] ?? 0).toStringAsFixed(0)}'),
          trailing: Text(
            '${product['soldCount'] ?? 0} sold',
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
          ),
        );
      },
    );
  }

  Widget _buildRevenueChart() {
    if (_revenueByDay.isEmpty) {
      return Center(
        child: Text(context.tr('no_data'), style: TextStyle(color: Colors.grey[500])),
      );
    }

    final maxRevenue = _revenueByDay.map((e) => e['revenue'] as double).reduce((a, b) => a > b ? a : b);

    return SizedBox(
      height: 200,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: _revenueByDay.map((data) {
          final height = maxRevenue > 0 ? ((data['revenue'] as double) / maxRevenue) * 160 : 0.0;
          return Expanded(
            child: Tooltip(
              message: 'TSh ${(data['revenue'] as double).toStringAsFixed(0)}\n${data['date']}',
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1),
                height: height + 20,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      width: double.infinity,
                      height: height,
                      decoration: BoxDecoration(
                        color: Colors.green.shade300,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      data['date'].toString().split('-').last,
                      style: const TextStyle(fontSize: 8),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
