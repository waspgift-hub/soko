import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../main.dart';
import '../../data/marketplace_taxonomy.dart';
import '../../models/category_model.dart';
import '../../services/category_service.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../utils/category_icons.dart';
import '../../widgets/marketplace/category_image.dart';
import '../../widgets/inputs/soko_search_bar.dart';
import '../../widgets/staggered_fade_in.dart';

/// Visual marketplace explorer: search, popular categories, then the full
/// responsive grid. Images lead, names stay visible for accessibility.
class CategoryScreen extends StatefulWidget {
  const CategoryScreen({super.key});

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
          context.tr('categories'),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppInsets.lg,
                0,
                AppInsets.lg,
                AppInsets.sm,
              ),
              child: SokoSearchBar(
                hint: context.tr('search_categories_hint'),
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<Category>>(
                stream: CategoryService().getCategories(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const _LoadingGrid();
                  }
                  if (snapshot.hasError) {
                    return _ErrorView(
                      onRetry: () => setState(() {}),
                    );
                  }
                  final cats = _visible(snapshot.data ?? []);
                  if (cats.isEmpty) {
                    return _EmptyCategoriesView(
                      colorScheme: cs,
                      filtering: _query.isNotEmpty,
                      onClear: () => setState(() => _query = ''),
                    );
                  }
                  return _Explorer(cats: cats, searching: _query.isNotEmpty);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Active Firestore categories matching the explorer query.
  List<Category> _visible(List<Category> cats) {
    final q = _query.toLowerCase();
    final active = cats.where((c) => c.isActive).toList();
    if (q.isEmpty) return active;
    bool hit(Category c) {
      if (c.name.toLowerCase().contains(q) ||
          c.nameSw.toLowerCase().contains(q)) {
        return true;
      }
      final tax = taxonomyById(c.id);
      if (tax != null &&
          tax.aliases.any((a) => a.toLowerCase().contains(q))) {
        return true;
      }
      return c.subcategories.any((s) =>
          s.name.toLowerCase().contains(q) ||
          s.nameSw.toLowerCase().contains(q));
    }

    return active.where(hit).toList();
  }
}

int _gridColumns(BuildContext context) {
  final w = MediaQuery.of(context).size.width;
  if (w >= 1200) return 6;
  if (w >= 900) return 5;
  if (w >= 700) return 4;
  if (w >= 600) return 3;
  return 2;
}

class _Explorer extends StatelessWidget {
  final List<Category> cats;
  final bool searching;
  const _Explorer({required this.cats, required this.searching});

  @override
  Widget build(BuildContext context) {
    final popular =
        cats.where((c) => taxonomyById(c.id)?.popular == true).toList();
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (!searching && popular.isNotEmpty) ...[
          _SectionTitle(title: context.tr('popular_categories')),
          SizedBox(
            height: 148,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppInsets.lg),
              itemCount: popular.length,
              itemBuilder: (context, i) => StaggeredFadeIn(
                index: i,
                child: _PopularCard(category: popular[i]),
              ),
            ),
          ),
          const SizedBox(height: AppInsets.sm),
        ],
        _SectionTitle(
          title: searching ? context.tr('results') : context.tr('all_categories'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppInsets.lg,
            0,
            AppInsets.lg,
            AppInsets.lg,
          ),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _gridColumns(context),
              crossAxisSpacing: AppInsets.md,
              mainAxisSpacing: AppInsets.md,
              childAspectRatio: 0.72,
            ),
            itemCount: cats.length,
            itemBuilder: (context, index) {
              final cat = cats[index];
              final config = AppConfig.of(context);
              return StaggeredFadeIn(
                index: index,
                child: Semantics(
                  button: true,
                  label: config.langCode == 'en' ? cat.name : cat.nameSw,
                  child: _PremiumCategoryCard(
                    category: cat,
                    name: config.langCode == 'en' ? cat.name : cat.nameSw,
                    langEn: config.langCode == 'en',
                    onTap: () => context.push(
                      '${AppRoutes.categoryProducts}/${cat.name}',
                      extra: cat,
                    ),
                    onSubTap: (sub) => context.push(
                      '${AppRoutes.categoryProducts}/${cat.name}'
                      '?sub=${Uri.encodeComponent(sub.name)}',
                      extra: cat,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(
          height: MediaQuery.of(context).padding.bottom + AppInsets.lg,
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppInsets.lg,
        AppInsets.sm,
        AppInsets.lg,
        AppInsets.xs,
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}

class _PopularCard extends StatelessWidget {
  final Category category;
  const _PopularCard({required this.category});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final config = AppConfig.of(context);
    return GestureDetector(
      onTap: () => context.push(
        '${AppRoutes.categoryProducts}/${category.name}',
        extra: category,
      ),
      child: Container(
        width: 168,
        margin: const EdgeInsets.only(right: AppInsets.md),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: CategoryImage(
                  imageUrl: category.displayImage,
                  fallback: categoryIconFor(
                    icon: category.icon,
                    slug: category.id,
                    name: category.name,
                  ),
                  memCacheSize: 320,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              child: Text(
                config.langCode == 'en' ? category.name : category.nameSw,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumCategoryCard extends StatelessWidget {
  final Category category;
  final String name;
  final bool langEn;
  final VoidCallback onTap;
  final ValueChanged<SubCategory> onSubTap;

  const _PremiumCategoryCard({
    required this.category,
    required this.name,
    required this.langEn,
    required this.onTap,
    required this.onSubTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final artwork = category.displayImage;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceVariant.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: cs.brandBorder, width: 1),
        ),
        child: Stack(
          children: [
            if (artwork != null)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: CategoryImage(
                    imageUrl: artwork,
                    fallback: categoryIconFor(
                      icon: category.icon,
                      slug: category.id,
                      name: category.name,
                    ),
                    memCacheSize: 400,
                  ),
                ),
              ),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      cs.surface.withValues(alpha: 0.8),
                      cs.surface,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (artwork == null)
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        categoryIconFor(
                          icon: category.icon,
                          slug: category.id,
                          name: category.name,
                        ),
                        color: cs.primary,
                        size: 20,
                      ),
                    ),
                  if (artwork == null) const SizedBox(height: 12),
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (category.subcategories.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (final sub
                            in category.subcategories.take(2))
                          Flexible(
                            child: GestureDetector(
                              onTap: () => onSubTap(sub),
                              child: Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.surface.withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: cs.outlineVariant,
                                  ),
                                ),
                                child: Text(
                                  langEn ? sub.name : sub.nameSw,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                        if (category.subcategories.length > 2)
                          Text(
                            '+${category.subcategories.length - 2}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingGrid extends StatelessWidget {
  const _LoadingGrid();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GridView.builder(
      padding: const EdgeInsets.all(AppInsets.lg),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _gridColumns(context),
        crossAxisSpacing: AppInsets.md,
        mainAxisSpacing: AppInsets.md,
        childAspectRatio: 0.72,
      ),
      itemCount: 8,
      itemBuilder: (context, _) => Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(24),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 64,
            color: cs.onSurface.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          TextButton(onPressed: onRetry, child: Text(context.tr('reset'))),
        ],
      ),
    );
  }
}

class _EmptyCategoriesView extends StatelessWidget {
  final ColorScheme colorScheme;
  final bool filtering;
  final VoidCallback onClear;
  const _EmptyCategoriesView({
    required this.colorScheme,
    this.filtering = false,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
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
              Icons.category_outlined,
              size: 80,
              color: colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 24),
            Text(
              filtering
                  ? context.tr('no_results')
                  : context.tr('no_categories'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            if (filtering) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: onClear,
                child: Text(context.tr('clear_all')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
