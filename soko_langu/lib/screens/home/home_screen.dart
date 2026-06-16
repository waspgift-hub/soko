import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../main.dart';
import '../../services/product_service.dart';
import '../../services/localization_service.dart';
import '../../services/category_service.dart';
import '../../models/product_model.dart';
import '../../models/category_model.dart';
import '../../widgets/product_card.dart';
import '../../widgets/ad_banner.dart';
import '../../widgets/dynamic_banner.dart';
import '../../widgets/flash_sale_banner.dart';
import '../../widgets/price_drop_banner.dart';
import '../../extensions/context_tr.dart';
import '../../utils/responsive.dart';
import '../../app/routes.dart';
import '../../widgets/google_loading.dart';
import '../../services/flash_sale_service.dart';
import '../../models/flash_sale_model.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {

  @override
  bool get wantKeepAlive => true;
  final ProductService _productService = ProductService();
  final FlashSaleService _flashSaleService = FlashSaleService();
  String? _selectedBrand;
  bool _pageLoaded = false;
  int _retryKey = 0;
  final _searchCtrl = TextEditingController();
  Map<String, FlashSale> _flashSales = {};
  StreamSubscription? _flashSub;
  int _flashRefreshKey = 0;
  List<String> _brands = [
    'Nike',
    'Adidas',
    'Samsung',
    'Apple',
    'Sony',
    'LG',
    'Toyota',
    'Hp',
    'Dell',
    'Other',
  ];

  void _showCurrencyPicker(BuildContext context) {
    final config = AppConfig.of(context);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                context.tr('select_currency'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ...LocalizationService.supportedCurrencies.entries.map(
              (e) => ListTile(
                title: Text("${e.value['name']} (${e.value['symbol']})"),
                trailing: config.currencyCode == e.key
                    ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () {
                  LocalizationService().setCurrency(e.key);
                  config.onSetCurrency(e.key);
                  Navigator.pop(ctx);
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscribeFlashSales();
  }

  void _subscribeFlashSales() {
    _flashSub?.cancel();
    final now = DateTime.now();
    _flashSub = _flashSaleService
        .getActiveFlashSalesMapAtNow(now)
        .listen(
      (map) {
        if (mounted) setState(() => _flashSales = map);
      },
      onError: (e) {
        debugPrint('Flash sales stream error: $e');
      },
    );
  }


  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
_searchCtrl.dispose();
    _flashSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() => _flashRefreshKey++);
      _subscribeFlashSales();
    }
  }

  Widget _brandChip(String label, String? brand) {
    final isSelected = _selectedBrand == brand;
    return GestureDetector(
      onTap: () => setState(() => _selectedBrand = brand),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outline,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Theme.of(context).colorScheme.surface : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        title: Text(
          context.tr('main_market'),
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w900,
            fontSize: 28,
            fontStyle: FontStyle.italic,
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.monetization_on_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            onPressed: () => _showCurrencyPicker(context),
          ),
          IconButton(
            icon: Icon(
              Icons.notifications_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            onPressed: () => context.push(AppRoutes.notifications),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom + 80,
          ),
          child: Column(
            children: [
              // Search bar
              RepaintBoundary(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 1.5,
                      ),
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      readOnly: true,
                      onTap: () => context.push(AppRoutes.search),
                      decoration: InputDecoration(
                        hintText: context.tr('search_products'),
                        hintStyle: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 14,
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          color: Theme.of(context).colorScheme.primary,
                          size: 22,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Brand chips
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _brandChip('All', null),
                    ..._brands.map((b) => _brandChip(b, b)),
                  ],
                ),
              ),
              // Flash Sale banner
              FlashSaleBanner(key: ValueKey('flash_banner_$_flashRefreshKey'), sales: _flashSales.values.toList()),
              // Price Drop banner
              const PriceDropBanner(),
              // Categories header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  children: [
                    Text(
                      context.tr('categories'),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.85),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => context.push(AppRoutes.category),
                      child: Text(
                        context.tr('see_all'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                      height: 100,
                      child: StreamBuilder<List<Category>>(
                        stream: CategoryService().getCategories(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return Center(
                              child: GoogleLoading(size: 24, strokeWidth: 2),
                            );
                          }
                          final cats = snapshot.data!;
                          if (cats.isEmpty) {
                            return Center(
                  child: Text(
                    context.tr('no_categories'),
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6), fontSize: 13),
                  ),
                            );
                          }
                          return ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: cats.length,
                            itemBuilder: (context, index) {
                              final cat = cats[index];
                              final config = AppConfig.of(context);
                              return GestureDetector(
                                onTap: () => context.push(
                                  '${AppRoutes.categoryProducts}/${cat.name}',
                                  extra: cat,
                                ),
                                child: Container(
                                  width: 80,
                                  margin: const EdgeInsets.only(right: 12),
                                  child: Column(
                                    children: [
                                              Container(
                                                width: 60,
                                                height: 60,
                                                decoration: BoxDecoration(
                                                  borderRadius: BorderRadius.circular(16),
                                                  border: Border.all(
                                                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                                                    width: 1.5,
                                                  ),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.04),
                                                      blurRadius: 8,
                                                      offset: const Offset(0, 3),
                                                    ),
                                                  ],
                                                ),
                                        child: Center(
                                          child: Text(
                                            cat.icon,
                                            style: const TextStyle(fontSize: 30),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        config.langCode == 'en' ? cat.name : cat.nameSw,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
              // Trending
              const DynamicBanner(),
              const SizedBox(height: 4),
              // Products area
              _buildProductsArea(),
              const SizedBox(height: 16),
              const AdBanner(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          gradient: LinearGradient(
            colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.tertiary],
          ),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: () => context.push(AppRoutes.addProduct),
          backgroundColor: Colors.transparent,
          label: Text(
            context.tr('sell_product'),
            style: TextStyle(
              color: Theme.of(context).colorScheme.surface,
              fontWeight: FontWeight.w600,
            ),
          ),
          icon: Icon(Icons.add, color: Theme.of(context).colorScheme.surface),
        ),
      ),
    );
  }

  Widget _buildProductsArea() {
    return StreamBuilder<List<Product>>(
      key: ValueKey('products_${_selectedBrand ?? 'all'}_$_retryKey'),
      stream: _selectedBrand == null
          ? _productService.getProducts()
          : _productService.getProductsByBrand(_selectedBrand!),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData && !snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: GoogleLoadingPage(),
          );
        }
        if (!_pageLoaded && (snap.hasData || snap.hasError)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _pageLoaded = true);
          });
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    context.tr('latest_products'),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                if (snap.hasError) {
                  final err = snap.error.toString();
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Icon(
                              Icons.cloud_off,
                              size: 48,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              context.tr('something_wrong'),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              err.contains('permission-denied')
                                  ? context.tr('permission_denied')
                                  : err.contains('UNAVAILABLE')
                                  ? context.tr('no_network')
                                  : context.tr('please_try_again'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () => setState(() => _retryKey++),
                              icon: const Icon(Icons.refresh, size: 18),
                              label: Text(context.tr('try_again')),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Theme.of(context).colorScheme.primary,
                                foregroundColor: Theme.of(context).colorScheme.surface,
                              ),
                            ),
                          ],
                        ),
                    ),
                  );
                }
                final products = snap.data ?? [];
                if (products.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Icon(Icons.inventory_2, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          const SizedBox(height: 12),
                          Text(
                            _selectedBrand == null
                                ? context.tr('no_products')
                                : '${context.tr('no_products_for')} $_selectedBrand',
                            style: TextStyle(
                              fontSize: 16,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: Responsive.gridColumns(context),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: Responsive.cardAspectRatio(context),
                  ),
                  itemCount: products.length,
                  itemBuilder: (context, index) => RepaintBoundary(
                    child: ProductCard(
                      product: products[index],
                      flashSale: _flashSales[products[index].id],
                      onTap: () => context.push(
                        '${AppRoutes.productDetail}/${products[index].id}',
                        extra: products[index],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

}
