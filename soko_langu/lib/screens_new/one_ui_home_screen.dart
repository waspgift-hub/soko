import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../app/routes.dart';
import '../../providers/product_feed_provider.dart';
import '../../models/product_model.dart';
import '../design_system/tokens/one_ui_tokens.dart';

class OneUiHomeScreen extends StatefulWidget {
  const OneUiHomeScreen({super.key});

  @override
  State<OneUiHomeScreen> createState() => _OneUiHomeScreenState();
}

class _OneUiHomeScreenState extends State<OneUiHomeScreen> with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  late AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: OneUiAnimation.slow,
      vsync: this,
    );
    _fadeController.forward();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProductFeedProvider>().loadInitial();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final feed = context.watch<ProductFeedProvider>();
    
    return Scaffold(
      backgroundColor: isDark ? OneUiColors.darkBackground : OneUiColors.background,
      body: FadeTransition(
        opacity: _fadeController,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(),
          slivers: [
            // App Bar
            SliverAppBar(
              floating: true,
              snap: true,
              backgroundColor: isDark ? OneUiColors.darkBackground : OneUiColors.background,
              elevation: 0,
              toolbarHeight: 64,
              title: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: OneUiColors.accent,
                      borderRadius: BorderRadius.circular(OneUiRadius.sm),
                    ),
                    child: const Icon(Icons.storefront, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: OneUiSpacing.md),
                  Text(
                    'Soko Vibe',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      color: isDark ? OneUiColors.darkTextPrimary : OneUiColors.textPrimary,
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  onPressed: () => context.push(AppRoutes.search),
                  icon: Icon(
                    Icons.search_rounded,
                    color: isDark ? OneUiColors.darkTextPrimary : OneUiColors.textPrimary,
                    size: 26,
                  ),
                ),
                IconButton(
                  onPressed: () => context.push(AppRoutes.notifications),
                  icon: Icon(
                    Icons.notifications_none_rounded,
                    color: isDark ? OneUiColors.darkTextPrimary : OneUiColors.textPrimary,
                    size: 26,
                  ),
                ),
                const SizedBox(width: OneUiSpacing.sm),
              ],
            ),
            
            // Categories
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(OneUiSpacing.xl, OneUiSpacing.sm, OneUiSpacing.xl, OneUiSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Categories',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        color: isDark ? OneUiColors.darkTextPrimary : OneUiColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: OneUiSpacing.lg),
                    SizedBox(
                      height: 90,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        itemCount: 8,
                        itemBuilder: (context, index) {
                          final categories = [
                            {'icon': Icons.phone_android_rounded, 'label': 'Electronics'},
                            {'icon': Icons.checkroom_rounded, 'label': 'Fashion'},
                            {'icon': Icons.home_rounded, 'label': 'Home'},
                            {'icon': Icons.directions_car_rounded, 'label': 'Vehicles'},
                            {'icon': Icons.sports_soccer_rounded, 'label': 'Sports'},
                            {'icon': Icons.pets_rounded, 'label': 'Pets'},
                            {'icon': Icons.build_rounded, 'label': 'Services'},
                            {'icon': Icons.more_horiz_rounded, 'label': 'More'},
                          ];
                          final cat = categories[index];
                          return Padding(
                            padding: EdgeInsets.only(right: index == 7 ? 0 : OneUiSpacing.lg),
                            child: GestureDetector(
                              onTap: () {
                                HapticFeedback.lightImpact();
                              },
                              child: Column(
                                children: [
                                  Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      color: isDark ? OneUiColors.darkSurface : OneUiColors.surface,
                                      borderRadius: BorderRadius.circular(OneUiRadius.lg),
                                      border: Border.all(
                                        color: isDark ? OneUiColors.darkBorder : OneUiColors.border,
                                        width: 0.5,
                                      ),
                                    ),
                                    child: Icon(
                                      cat['icon'] as IconData,
                                      color: OneUiColors.accent,
                                      size: 28,
                                    ),
                                  ),
                                  const SizedBox(height: OneUiSpacing.sm),
                                  SizedBox(
                                    width: 64,
                                    child: Text(
                                      cat['label'] as String,
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark ? OneUiColors.darkTextSecondary : OneUiColors.textSecondary,
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
                ),
              ),
            ),
            
            // Products header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(OneUiSpacing.xl, OneUiSpacing.sm, OneUiSpacing.xl, OneUiSpacing.lg),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'For You',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        color: isDark ? OneUiColors.darkTextPrimary : OneUiColors.textPrimary,
                      ),
                    ),
                    TextButton(
                      onPressed: () {},
                      child: const Text('See all'),
                    ),
                  ],
                ),
              ),
            ),
            
            // Products grid
            if (feed.isLoading && feed.products.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(OneUiSpacing.xxl),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (feed.products.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(OneUiSpacing.xxl),
                  child: Column(
                    children: [
                      Icon(
                        Icons.shopping_bag_outlined,
                        size: 64,
                        color: isDark ? OneUiColors.darkTextTertiary : OneUiColors.textTertiary,
                      ),
                      const SizedBox(height: OneUiSpacing.lg),
                      Text(
                        'No products yet',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isDark ? OneUiColors.darkTextPrimary : OneUiColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: OneUiSpacing.sm),
                      Text(
                        'Check back later for new items',
                        style: TextStyle(
                          color: isDark ? OneUiColors.darkTextSecondary : OneUiColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: OneUiSpacing.xl),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.68,
                    crossAxisSpacing: OneUiSpacing.md,
                    mainAxisSpacing: OneUiSpacing.lg,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final product = feed.products[index];
                      return _OneUiProductCard(product: product);
                    },
                    childCount: feed.products.length,
                  ),
                ),
              ),
            
            const SliverToBoxAdapter(
              child: SizedBox(height: 100),
            ),
          ],
        ),
      ),
    );
  }
}

class _OneUiProductCard extends StatelessWidget {
  final Product product;
  const _OneUiProductCard({required this.product});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final imageUrl = product.images.isNotEmpty ? product.images.first : null;
    
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        context.push('/oneui/product', extra: product);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: isDark ? OneUiColors.darkSurface : OneUiColors.surfaceVariant,
                borderRadius: BorderRadius.circular(OneUiRadius.lg),
                border: Border.all(
                  color: isDark ? OneUiColors.darkBorder : OneUiColors.border,
                  width: 0.5,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(OneUiRadius.lg - 1),
                child: imageUrl != null
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Center(
                          child: Icon(
                            Icons.image_outlined,
                            color: isDark ? OneUiColors.darkTextTertiary : OneUiColors.textTertiary,
                            size: 32,
                          ),
                        ),
                      )
                    : Center(
                        child: Icon(
                          Icons.image_outlined,
                          color: isDark ? OneUiColors.darkTextTertiary : OneUiColors.textTertiary,
                          size: 32,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: OneUiSpacing.sm),
          Text(
            product.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.3,
              color: isDark ? OneUiColors.darkTextPrimary : OneUiColors.textPrimary,
            ),
          ),
          const SizedBox(height: OneUiSpacing.xs),
          Text(
            'TSh ${_formatPrice(product.price)}',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: OneUiColors.accent,
            ),
          ),
          if (product.location.isNotEmpty) ...[
            const SizedBox(height: OneUiSpacing.xs),
            Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 12,
                  color: isDark ? OneUiColors.darkTextTertiary : OneUiColors.textTertiary,
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: Text(
                    product.location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? OneUiColors.darkTextTertiary : OneUiColors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _formatPrice(double price) {
    final p = price.round();
    return p.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }
}
