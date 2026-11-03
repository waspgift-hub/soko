import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../design_system/tokens/one_ui_tokens.dart';
import '../../models/product_model.dart';

class OneUiProductDetailScreen extends StatefulWidget {
  final Product product;
  const OneUiProductDetailScreen({super.key, required this.product});

  @override
  State<OneUiProductDetailScreen> createState() => _OneUiProductDetailScreenState();
}

class _OneUiProductDetailScreenState extends State<OneUiProductDetailScreen> {
  int _currentImageIndex = 0;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final product = widget.product;
    final images = product.images.isNotEmpty ? product.images : [''];
    
    return Scaffold(
      backgroundColor: isDark ? OneUiColors.darkBackground : OneUiColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 400,
            pinned: true,
            backgroundColor: isDark ? OneUiColors.darkBackground : OneUiColors.background,
            leading: IconButton(
              onPressed: () => context.pop(),
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (isDark ? OneUiColors.darkSurface : OneUiColors.surface).withOpacity(0.9),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: isDark ? OneUiColors.darkTextPrimary : OneUiColors.textPrimary),
              ),
            ),
            actions: [
              IconButton(
                onPressed: () => HapticFeedback.lightImpact(),
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (isDark ? OneUiColors.darkSurface : OneUiColors.surface).withOpacity(0.9),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.share_outlined, size: 18, color: isDark ? OneUiColors.darkTextPrimary : OneUiColors.textPrimary),
                ),
              ),
              IconButton(
                onPressed: () => HapticFeedback.lightImpact(),
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (isDark ? OneUiColors.darkSurface : OneUiColors.surface).withOpacity(0.9),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.favorite_border_rounded, size: 18, color: isDark ? OneUiColors.darkTextPrimary : OneUiColors.textPrimary),
                ),
              ),
              const SizedBox(width: OneUiSpacing.sm),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: PageView.builder(
                itemCount: images.length,
                onPageChanged: (index) => setState(() => _currentImageIndex = index),
                itemBuilder: (context, index) {
                  return images[index].isEmpty
                      ? Container(
                          color: isDark ? OneUiColors.darkSurfaceContainer : OneUiColors.surfaceVariant,
                          child: Icon(Icons.image_outlined, size: 64, color: isDark ? OneUiColors.darkTextTertiary : OneUiColors.textTertiary),
                        )
                      : Image.network(
                          images[index],
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: isDark ? OneUiColors.darkSurfaceContainer : OneUiColors.surfaceVariant,
                            child: Icon(Icons.image_outlined, size: 64, color: isDark ? OneUiColors.darkTextTertiary : OneUiColors.textTertiary),
                          ),
                        );
                },
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (images.length > 1)
                  Padding(
                    padding: const EdgeInsets.all(OneUiSpacing.xl),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        images.length,
                        (index) => Container(
                          width: _currentImageIndex == index ? 24 : 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: _currentImageIndex == index ? OneUiColors.accent : (isDark ? OneUiColors.darkBorder : OneUiColors.border),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: OneUiSpacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.3,
                          color: isDark ? OneUiColors.darkTextPrimary : OneUiColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: OneUiSpacing.sm),
                      Text(
                        'TSh ${_formatPrice(product.price)}',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: OneUiColors.accent,
                        ),
                      ),
                      const SizedBox(height: OneUiSpacing.lg),
                      if (product.location.isNotEmpty)
                        Row(
                          children: [
                            Icon(Icons.location_on_outlined, size: 18, color: isDark ? OneUiColors.darkTextSecondary : OneUiColors.textSecondary),
                            const SizedBox(width: OneUiSpacing.xs),
                            Text(product.location, style: TextStyle(color: isDark ? OneUiColors.darkTextSecondary : OneUiColors.textSecondary)),
                          ],
                        ),
                      const SizedBox(height: OneUiSpacing.xxl),
                      Text(
                        'Description',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: isDark ? OneUiColors.darkTextPrimary : OneUiColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: OneUiSpacing.md),
                      Text(
                        product.description.isNotEmpty ? product.description : 'No description provided.',
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.6,
                          color: isDark ? OneUiColors.darkTextSecondary : OneUiColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: OneUiSpacing.xxl),
                      Container(
                        padding: const EdgeInsets.all(OneUiSpacing.lg),
                        decoration: BoxDecoration(
                          color: isDark ? OneUiColors.darkSurface : OneUiColors.surface,
                          borderRadius: BorderRadius.circular(OneUiRadius.lg),
                          border: Border.all(color: isDark ? OneUiColors.darkBorder : OneUiColors.border, width: 0.5),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: OneUiColors.accentContainer,
                              child: Icon(Icons.person, color: OneUiColors.accent),
                            ),
                            const SizedBox(width: OneUiSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Seller',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? OneUiColors.darkTextPrimary : OneUiColors.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    'View profile',
                                    style: TextStyle(fontSize: 13, color: OneUiColors.accent),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded, color: isDark ? OneUiColors.darkTextTertiary : OneUiColors.textTertiary),
                          ],
                        ),
                      ),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(OneUiSpacing.lg),
        decoration: BoxDecoration(
          color: isDark ? OneUiColors.darkSurface : OneUiColors.surface,
          border: Border(top: BorderSide(color: isDark ? OneUiColors.darkBorder : OneUiColors.border, width: 0.5)),
        ),
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => HapticFeedback.lightImpact(),
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                  label: const Text('Chat'),
                ),
              ),
              const SizedBox(width: OneUiSpacing.md),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: () => HapticFeedback.mediumImpact(),
                  icon: const Icon(Icons.shopping_cart_outlined),
                  label: const Text('Contact Seller'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatPrice(double price) {
    final p = price.round();
    return p.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
  }
}
