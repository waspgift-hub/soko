import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../main.dart';
import '../../models/category_model.dart';
import '../../services/category_service.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/google_loading.dart';
import '../../utils/responsive.dart';

class CategoryScreen extends StatefulWidget {
  const CategoryScreen({super.key});

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final value = _searchController.text.trim().toLowerCase();
      if (value != _query) setState(() => _query = value);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Category> _visibleCategories(List<Category> categories) {
    if (_query.isEmpty) return categories;
    return categories.where((category) {
      final parentMatch = category.name.toLowerCase().contains(_query) ||
          category.nameSw.toLowerCase().contains(_query);
      final childMatch = category.subcategories.any(
        (sub) =>
            sub.name.toLowerCase().contains(_query) ||
            sub.nameSw.toLowerCase().contains(_query),
      );
      return parentMatch || childMatch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(context.tr('categories')),
        actions: [
          IconButton(
            tooltip: context.tr('search'),
              icon: const Icon(Icons.search_rounded),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: StreamBuilder<List<Category>>(
          stream: CategoryService().getCategories(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const GoogleLoadingPage();
            }

            final categories = _visibleCategories(snapshot.data ?? []);
            if (categories.isEmpty) {
              return _EmptyCategoriesView(
                colorScheme: cs,
                filtered: _query.isNotEmpty,
              );
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                final isDesktop = constraints.maxWidth >= 1000;
                final columns = isDesktop
                    ? 4
                    : Responsive.gridColumns(context);

                return CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppInsets.lg,
                          AppInsets.xs,
                          AppInsets.lg,
                          AppInsets.sm,
                        ),
                        child: _CategoryIntro(
                          controller: _searchController,
                          count: categories.length,
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        AppInsets.lg,
                        AppInsets.sm,
                        AppInsets.lg,
                        AppInsets.xxl,
                      ),
                      sliver: SliverGrid(
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: AppInsets.md,
                          mainAxisSpacing: AppInsets.md,
                          childAspectRatio: isDesktop ? 1.15 : 1.02,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final category = categories[index];
                            final config = AppConfig.of(context);
                            final name = config.langCode == 'en'
                                ? category.name
                                : category.nameSw;
                            return _CategoryCard(
                              name: name,
                              secondaryName: config.langCode == 'en'
                                  ? category.nameSw
                                  : category.name,
                              icon: categoryIconFor(category.icon),
                              subcategoryCount:
                                  category.subcategories.length,
                              onTap: () => context.push(
                                '\${AppRoutes.categoryProducts}/\${category.name}',
                                extra: category,
                              ),
                            );
                          },
                          childCount: categories.length,
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _CategoryIntro extends StatelessWidget {
  final TextEditingController controller;
  final int count;

  const _CategoryIntro({
    required this.controller,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr(
            'shop_by_category',
            'Shop by category',
          ),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
        ),
        const SizedBox(height: 5),
        Text(
          context.tr(
            'physical_products_only',
            'Browse physical products from trusted sellers.',
          ),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: controller,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: context.tr(
              'search_categories',
              'Search categories',
            ),
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                if (value.text.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Center(
                      widthFactor: 1,
                      child: Text(
                        '\$count',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                }
                return IconButton(
                  tooltip: context.tr('clear'),
                  onPressed: controller.clear,
                  icon: const Icon(Icons.close_rounded),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _CategoryCard extends StatefulWidget {
  final String name;
  final String secondaryName;
  final IconData icon;
  final int subcategoryCount;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.name,
    required this.secondaryName,
    required this.icon,
    required this.subcategoryCount,
    required this.onTap,
  });

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        transform: Matrix4.identity()
          ..translate(0.0, _hovered ? -2.0 : 0.0),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: _hovered
                ? cs.primary.withValues(alpha: 0.55)
                : cs.outlineVariant,
          ),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: cs.primary.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ]
              : const [],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(22),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(
                            alpha: _hovered ? 0.16 : 0.10,
                          ),
                          borderRadius: BorderRadius.circular(17),
                        ),
                        child: Icon(
                          widget.icon,
                          color: cs.primary,
                          size: 27,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 20,
                        color: _hovered
                            ? cs.primary
                            : cs.onSurfaceVariant.withValues(alpha: 0.65),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    widget.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    widget.secondaryName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      Icon(
                        Icons.grid_view_rounded,
                        size: 14,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        widget.subcategoryCount == 1
                            ? context.tr('subcategory', 'subcategory')
                            : context.tr('subcategories', 'subcategories'),
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                      const Spacer(),
                      Text(
                        '\${widget.subcategoryCount}',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyCategoriesView extends StatelessWidget {
  final ColorScheme colorScheme;
  final bool filtered;

  const _EmptyCategoriesView({
    required this.colorScheme,
    required this.filtered,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppInsets.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              filtered
                  ? Icons.search_off_rounded
                  : Icons.category_outlined,
              size: 64,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 16),
            Text(
              filtered
                  ? context.tr(
                      'no_categories_matching',
                      'No categories match your search.',
                    )
                  : context.tr('no_categories'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData categoryIconFor(String glyph) {
  switch (glyph.trim().toLowerCase()) {
    case 'electronics':
    case '📱':
      return Icons.devices_other_rounded;
    case 'phones_tablets':
      return Icons.phone_android_rounded;
    case 'fashion':
    case '👕':
    case '👗':
      return Icons.checkroom_rounded;
    case 'home_living':
    case '🏠':
    case '🛋️':
    case '🪑':
      return Icons.home_work_outlined;
    case 'beauty':
    case '💄':
      return Icons.auto_awesome_outlined;
    case 'vehicles':
    case '🚗':
      return Icons.directions_car_filled_outlined;
    case 'agriculture':
    case '🌾':
      return Icons.agriculture_outlined;
    case 'food':
    case '🍎':
    case '🍔':
    case '🥦':
      return Icons.shopping_basket_outlined;
    case 'sports':
    case '⚽':
    case '🏀':
      return Icons.sports_soccer_outlined;
    case 'baby':
    case '👶':
      return Icons.child_friendly_outlined;
    case 'business':
    case '🏭':
      return Icons.business_center_outlined;
    case 'tools':
    case '🔧':
      return Icons.handyman_outlined;
    case 'other':
    case 'other_physical':
    case '📦':
      return Icons.category_outlined;
    default:
      return Icons.category_outlined;
  }
}
