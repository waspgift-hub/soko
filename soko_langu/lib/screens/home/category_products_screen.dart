import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../main.dart';
import '../../extensions/context_tr.dart';
import '../../models/category_model.dart';
import '../../models/product_model.dart';
import '../../services/product_service.dart';
import '../../widgets/product_card.dart';
import '../../app/routes.dart';
import '../../widgets/google_loading.dart';

class CategoryProductsScreen extends StatefulWidget {
  final Category category;
  const CategoryProductsScreen({super.key, required this.category});

  @override
  State<CategoryProductsScreen> createState() => _CategoryProductsScreenState();
}

class _CategoryProductsScreenState extends State<CategoryProductsScreen> {
  final _productService = ProductService();
  String? _selectedSubcategory;

  @override
  Widget build(BuildContext context) {
    final hasSubcategories = widget.category.subcategories.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.category.nameSw, style: const TextStyle(fontSize: 16)),
            Text(
              widget.category.name,
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasSubcategories) _buildSubcategoryChips(),
            Expanded(child: _buildProductsGrid()),
          ],
        ),
      ),
    );
  }

  Widget _buildSubcategoryChips() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: widget.category.subcategories.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Container(
              margin: const EdgeInsets.only(right: 8, top: 10, bottom: 10),
              child: ChoiceChip(
                label: Text(
                  _selectedSubcategory == null ? '✓' : context.tr('all'),
                  style: const TextStyle(fontSize: 12),
                ),
                selected: _selectedSubcategory == null,
                onSelected: (_) => setState(() => _selectedSubcategory = null),
              ),
            );
          }
          final sub = widget.category.subcategories[index - 1];
          final isSelected = _selectedSubcategory == sub.name;
          final config = AppConfig.of(context);
          return Container(
            margin: const EdgeInsets.only(right: 8, top: 10, bottom: 10),
            child: ChoiceChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    config.langCode == 'en' ? sub.name : sub.nameSw,
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (isSelected) const SizedBox(width: 4),
                  if (isSelected)
                    Text(
                      '✓',
                      style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                    ),
                ],
              ),
              selected: isSelected,
              onSelected: (_) =>
                  setState(() => _selectedSubcategory = sub.name),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProductsGrid() {
    final stream = _selectedSubcategory == null
        ? _productService.getProductsByCategory(widget.category.name)
        : _productService.getProductsByCategoryAndSubcategory(
            widget.category.name,
            _selectedSubcategory!,
          );

    return StreamBuilder<List<Product>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const GoogleLoadingPage();
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + 20,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.shopping_bag_outlined,
                    size: 64,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    context.tr('no_products_category'),
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final products = snapshot.data!;
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.7,
          ),
          itemCount: products.length,
          itemBuilder: (context, index) {
            return ProductCard(
              product: products[index],
              onTap: () => context.push(
                '${AppRoutes.productDetail}/${products[index].id}',
                extra: products[index],
              ),
            );
          },
        );
      },
    );
  }
}
