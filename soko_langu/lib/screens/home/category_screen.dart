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
import '../../widgets/soko_widgets.dart';

class CategoryScreen extends StatelessWidget {
  const CategoryScreen({super.key});

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
        child: StreamBuilder<List<Category>>(
          stream: CategoryService().getCategories(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const GoogleLoadingPage();
            }
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return _EmptyCategoriesView(colorScheme: cs);
            }

            final categories = snapshot.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppInsets.lg, 0, AppInsets.lg, AppInsets.md),
                  child: Text(
                    context.tr('explore_physical_products', 'Explore our verified physical products'),
                    style: TextStyle(
                      fontSize: 14,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(AppInsets.lg),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: Responsive.gridColumns(context),
                      crossAxisSpacing: AppInsets.md,
                      mainAxisSpacing: AppInsets.md,
                      childAspectRatio: Responsive.cardAspectRatio(context),
                    ),
                    itemCount: categories.length,
                    itemBuilder: (context, index) {
                      final cat = categories[index];
                      final config = AppConfig.of(context);
                      return _PremiumCategoryCard(
                        name: config.langCode == 'en' ? cat.name : cat.nameSw,
                        icon: categoryIconFor(cat.icon),
                        imageUrl: cat.image,
                        onTap: () => context.push(
                          '${AppRoutes.categoryProducts}/${cat.name}',
                          extra: cat,
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PremiumCategoryCard extends StatelessWidget {
  final String name;
  final IconData icon;
  final String? imageUrl;
  final VoidCallback onTap;

  const _PremiumCategoryCard({
    required this.name,
    required this.icon,
    this.imageUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

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
            if (imageUrl != null && imageUrl!.isNotEmpty)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.network(
                    imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
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
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: cs.primary, size: 20),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.black, // Explicitly black for contrast on light theme, consider theme-aware
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCategoriesView extends StatelessWidget {
  final ColorScheme colorScheme;
  const _EmptyCategoriesView({required this.colorScheme});

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
              context.tr('no_categories'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData categoryIconFor(String glyph) {
  switch (glyph) {
    case '📦': return Icons.inventory_2_outlined;
    case '📱': return Icons.smartphone;
    case '👗':
    case '👕': return Icons.checkroom_outlined;
    case '👟': return Icons.ice_skating_outlined;
    case '💄': return Icons.face_retouching_natural;
    case '🛋️':
    case '🪑': return Icons.chair_outlined;
    case '⚽':
    case '🏀': return Icons.sports_soccer;
    case '📚': return Icons.menu_book_outlined;
    case '🎁': return Icons.card_giftcard_outlined;
    case '💎': return Icons.diamond_outlined;
    case '🔧': return Icons.build_outlined;
    case '🍎': return Icons.local_grocery_store_outlined;
    case '🛒': return Icons.shopping_cart_outlined;
    case '🚗': return Icons.directions_car_outlined;
    case '🏭': return Icons.factory_outlined;
    case '🍔':
    case '🥦': return Icons.fastfood_outlined;
    case '👶': return Icons.child_care_outlined;
    case '🏠': return Icons.home_outlined;
    default: return Icons.category_outlined;
  }
}
