import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../main.dart';
import '../../services/product_service.dart';
import '../../services/category_service.dart';
import '../../models/product_model.dart';
import '../../models/category_model.dart';
import '../../widgets/product_card.dart';
import '../../widgets/flash_sale_banner.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ProductService _productService = ProductService();
  String? _selectedBrand;
  bool _pageLoaded = false;
  int _retryKey = 0;
  final _searchCtrl = TextEditingController();
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

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Widget _brandChip(String label, String? brand) {
    final isSelected = _selectedBrand == brand;
    return GestureDetector(
      onTap: () => setState(() => _selectedBrand = brand),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2D6A4F) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF2D6A4F) : Colors.grey[300]!,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[700],
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        title: const Text(
          "Soko Kuu",
          style: TextStyle(
            color: Color(0xFF2D6A4F),
            fontWeight: FontWeight.w900,
            fontSize: 28,
            fontStyle: FontStyle.italic,
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.smart_toy_outlined,
              color: Color(0xFF2D6A4F),
            ),
            onPressed: () => context.push(AppRoutes.aiAssistant),
          ),
          IconButton(
            icon: const Icon(
              Icons.notifications_none,
              color: Color(0xFF2D6A4F),
            ),
            onPressed: () => context.push(AppRoutes.notifications),
          ),
          IconButton(
            icon: const Icon(Icons.search, color: Color(0xFF2D6A4F)),
            onPressed: () => context.push(AppRoutes.search),
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
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF2D6A4F),
                        width: 1.5,
                      ),
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      readOnly: true,
                      onTap: () => context.push(AppRoutes.search),
                      decoration: InputDecoration(
                        hintText: 'Search products...',
                        hintStyle: TextStyle(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : Colors.black,
                          fontSize: 14,
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          color: const Color(0xFF2D6A4F),
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
              const FlashSaleBanner(),
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
              const SizedBox(height: 8),
              // Categories
              RepaintBoundary(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            context.tr('categories'),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1B4332),
                            ),
                          ),
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
                            return const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            );
                          }
                          final cats = snapshot.data!;
                          if (cats.isEmpty) {
                            return Center(
                              child: Text(
                                'No categories yet',
                                style: TextStyle(color: Colors.grey[500], fontSize: 13),
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
                                                    color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                                                    width: 1.5,
                                                  ),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.black.withOpacity(0.04),
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
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // Boosted products
              _buildBoostedSection(),
              const SizedBox(height: 8),
              // Products area
              _buildProductsArea(),
              const SizedBox(height: 16),
              const FlashSaleBanner(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
      floatingActionButton: Container(
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          gradient: LinearGradient(
            colors: [Color(0xFF2D6A4F), Color(0xFF40916C)],
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x332D6A4F),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: () => context.push(AppRoutes.addProduct),
          backgroundColor: Colors.transparent,
          label: Text(
            context.tr('sell_product'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          icon: const Icon(Icons.add, color: Colors.white),
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
        if (snap.connectionState == ConnectionState.waiting && !_pageLoaded) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        if (!_pageLoaded && snap.hasData && snap.data!.isNotEmpty) {
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
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1B4332),
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
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Kuna tatizo limetokea!',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            err.contains('permission-denied')
                                ? 'Firestore permissions hazijafunguliwa.'
                                : err.contains('UNAVAILABLE')
                                ? 'Hakuna mtandao.'
                                : 'Tafadhali jaribu tena.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () => setState(() => _retryKey++),
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Jaribu tena'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2D6A4F),
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final products = snap.data ?? [];
                if (products.isEmpty && _pageLoaded) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Icon(Icons.inventory_2, size: 48, color: Colors.grey[400]),
                          const SizedBox(height: 12),
                          Text(
                            _selectedBrand == null
                                ? 'No products yet'
                                : 'No products for $_selectedBrand',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
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
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.72,
                  ),
                  itemCount: products.length,
                  itemBuilder: (context, index) => RepaintBoundary(
                    child: ProductCard(
                      product: products[index],
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

  Widget _buildBoostedSection() {
    return StreamBuilder<List<Product>>(
      stream: _productService.getBoostedProducts(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.isEmpty) {
          return const SizedBox.shrink();
        }
        final boosted = snap.data!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.local_fire_department, color: Colors.red.shade700, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    context.tr('boosted_products'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1B4332),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: boosted.length,
                itemBuilder: (context, index) {
                  final product = boosted[index];
                  return GestureDetector(
                    onTap: () => context.push(
                      '${AppRoutes.productDetail}/${product.id}',
                      extra: product,
                    ),
                    child: Container(
                      width: 200,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade100, width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.08),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(7),
                              bottomLeft: Radius.circular(7),
                            ),
                            child: Image.network(
                              product.images.isNotEmpty
                                  ? product.images.first
                                  : '',
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stack) => Container(
                                width: 80,
                                height: 80,
                                color: Colors.grey[200],
                                child: Icon(Icons.image, color: Colors.grey[400], size: 24),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.local_fire_department, color: Colors.red.shade600, size: 12),
                                      const SizedBox(width: 2),
                                      Text(
                                        'Trending',
                                        style: TextStyle(
                                          color: Colors.red.shade700,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    product.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      height: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'TSh ${product.price.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF2D6A4F),
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
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

