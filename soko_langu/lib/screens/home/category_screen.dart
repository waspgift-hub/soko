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
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('categories'))),
      body: SafeArea(
        child: StreamBuilder<List<Category>>(
          stream: CategoryService().getCategories(),
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
                        Icons.category,
                        size: 64,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                      SizedBox(height: 16),
                      Text(
                        context.tr('no_categories'),
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

            final categories = snapshot.data!;
            return GridView.builder(
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
                return CategoryCard(
                  name: config.langCode == 'en' ? cat.name : cat.nameSw,
                  icon: categoryIconFor(cat.icon),
                  imageUrl: cat.image,
                  onTap: () => context.push(
                    '${AppRoutes.categoryProducts}/${cat.name}',
                    extra: cat,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Maps legacy emoji category glyphs to monochrome Material icons so the grid
/// stays B&W-consistent; unmapped glyphs fall back to a generic catalog icon.
IconData categoryIconFor(String emoji) {
  switch (emoji) {
    case '📦':
      return Icons.inventory_2_outlined;
    case '📱':
      return Icons.smartphone;
    case '👗':
    case '👕':
      return Icons.checkroom_outlined;
    case '👟':
      return Icons.ice_skating_outlined;
    case '💄':
      return Icons.face_retouching_natural;
    case '🛋️':
    case '🪑':
      return Icons.chair_outlined;
    case '⚽':
    case '🏀':
      return Icons.sports_soccer;
    case '📚':
      return Icons.menu_book_outlined;
    case '🎁':
      return Icons.card_giftcard_outlined;
    case '💎':
      return Icons.diamond_outlined;
    case '🔧':
      return Icons.build_outlined;
    case '🍎':
      return Icons.local_grocery_store_outlined;
    case '🛒':
      return Icons.shopping_cart_outlined;
    case '🚗':
      return Icons.directions_car_outlined;
    case '🏭':
      return Icons.factory_outlined;
    case '🍔':
    case '🥦':
      return Icons.fastfood_outlined;
    case '👶':
      return Icons.child_care_outlined;
    case '🏠':
      return Icons.home_outlined;
    default:
      return Icons.category_outlined;
  }
}
