import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../main.dart';
import '../../models/category_model.dart';
import '../../services/category_service.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';
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
              padding: const EdgeInsets.all(16),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: Responsive.gridColumns(context),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: Responsive.cardAspectRatio(context),
              ),
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final cat = categories[index];
                final config = AppConfig.of(context);
                return GestureDetector(
                  onTap: () => context.push(
                    '${AppRoutes.categoryProducts}/${cat.name}',
                    extra: cat,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(cat.icon, style: const TextStyle(fontSize: 40)),
                        const SizedBox(height: 8),
                        Text(
                          config.langCode == 'en' ? cat.name : cat.nameSw,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
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
    );
  }
}
