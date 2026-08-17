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
                final cs = Theme.of(context).colorScheme;
                return Semantics(
                  button: true,
                  label: cat.name,
                  onTap: () => context.push(
                    '${AppRoutes.categoryProducts}/${cat.name}',
                    extra: cat,
                  ),
                  child: GestureDetector(
                    excludeFromSemantics: true,
                    onTap: () => context.push(
                      '${AppRoutes.categoryProducts}/${cat.name}',
                      extra: cat,
                    ),
                    child: Container(
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.6),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: cs.onSurface.withValues(alpha: cs.brightness == Brightness.dark ? 0.25 : 0.05),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                          ),
                          child: Text(cat.icon, style: const TextStyle(fontSize: 28)),
                        ),
                        SizedBox(height: AppInsets.md),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppInsets.sm),
                          child: Text(
                            config.langCode == 'en' ? cat.name : cat.nameSw,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: AppFontSize.md,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
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
