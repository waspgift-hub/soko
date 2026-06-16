import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/product_model.dart';
import '../../models/flash_sale_model.dart';
import '../../services/product_service.dart';
import '../../services/user_service.dart';
import '../../services/flash_sale_service.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/product_card.dart';
import '../../widgets/google_loading.dart';
import '../../widgets/verified_badge.dart';
import '../../app/routes.dart';
import '../../utils/responsive.dart';

class SellerProfileScreen extends StatefulWidget {
  final String sellerId;
  final String sellerName;

  const SellerProfileScreen({
    super.key,
    required this.sellerId,
    this.sellerName = '',
  });

  @override
  State<SellerProfileScreen> createState() => _SellerProfileScreenState();
}

class _SellerProfileScreenState extends State<SellerProfileScreen> {
  final FlashSaleService _flashSaleService = FlashSaleService();
  Map<String, FlashSale> _flashSales = {};
  StreamSubscription? _flashSub;

  @override
  void initState() {
    super.initState();
    _flashSub = _flashSaleService.getActiveFlashSalesMap().listen((map) {
      if (mounted) setState(() => _flashSales = map);
    });
  }

  @override
  void dispose() {
    _flashSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productService = ProductService();
    final userService = UserService();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.sellerName),
        actions: [
          IconButton(
            icon: Icon(Icons.message, color: Theme.of(context).colorScheme.primary),
            onPressed: () => context.push(
              '${AppRoutes.chat}/${widget.sellerId}',
              extra: {'name': widget.sellerName},
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<UserProfile?>(
          stream: userService.streamProfile(widget.sellerId),
          builder: (context, userSnap) {
            if (userSnap.connectionState == ConnectionState.waiting) {
              return const GoogleLoadingPage();
            }
            final profile = userSnap.data;
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildHeader(context, profile)),
                SliverToBoxAdapter(child: _buildActions(context)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      context.tr('products'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                StreamBuilder<List<Product>>(
                  stream: productService.getProducts(),
                  builder: (context, prodSnap) {
                    final all = prodSnap.data ?? [];
                    final products = all
                        .where((p) => p.sellerId == widget.sellerId)
                        .toList();

                    if (products.isEmpty) {
                      return SliverFillRemaining(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.shopping_bag_outlined,
                                size: 64,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                context.tr('no_products'),
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return SliverGrid(
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: Responsive.gridColumns(context),
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: Responsive.cardAspectRatio(context),
                          ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => ProductCard(
                          product: products[index],
                          flashSale: _flashSales[products[index].id],
                          onTap: () => context.push(
                            '${AppRoutes.productDetail}/${products[index].id}',
                            extra: products[index],
                          ),
                        ),
                        childCount: products.length,
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Color _parseColor(BuildContext context, String hex) {
    if (hex.isEmpty) return Theme.of(context).colorScheme.primary;
    hex = hex.replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }

  Widget _buildStorefront(BuildContext context, UserProfile? profile) {
    final hasStorefront =
        profile != null &&
        (profile.shopBanner.isNotEmpty || profile.shopBannerColor.isNotEmpty);
    if (!hasStorefront) return const SizedBox.shrink();

    final bannerColor = profile.shopBannerColor.isNotEmpty
        ? _parseColor(context, profile.shopBannerColor)
        : Theme.of(context).colorScheme.primary;
    final accent = profile.shopAccentColor.isNotEmpty
        ? _parseColor(context, profile.shopAccentColor)
        : Theme.of(context).colorScheme.primary;

    return Container(
      height: 140,
      width: double.infinity,
      decoration: BoxDecoration(
        color: bannerColor,
        image: profile.shopBanner.isNotEmpty
            ? DecorationImage(
                image: NetworkImage(profile.shopBanner),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: Container(
        alignment: Alignment.bottomLeft,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38)],
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Seller',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.surface,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, UserProfile? profile) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          _buildStorefront(context, profile),
          const SizedBox(height: 16),
          Stack(
            children: [
              CircleAvatar(
                radius: 50,
                backgroundColor: Theme.of(context).colorScheme.primary,
                backgroundImage: profile?.profileImage.isNotEmpty == true
                    ? NetworkImage(profile!.profileImage)
                    : null,
                child: profile?.profileImage.isEmpty != false
                    ? Text(
                        (profile?.displayName.isNotEmpty == true
                                ? profile!.displayName
                                : widget.sellerName)[0]
                            .toUpperCase(),
                        style: TextStyle(
                          fontSize: 40,
                          color: Theme.of(context).colorScheme.surface,
                        ),
                      )
                    : null,
              ),
              Positioned(
                right: 4,
                bottom: 4,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Theme.of(context).colorScheme.surface, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                profile?.displayName.isNotEmpty == true
                    ? profile!.displayName
                    : widget.sellerName,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (profile?.kycApproved == true)
                const VerifiedBadge(size: 16),
            ],
          ),
          if (profile?.bio.isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text(
              profile!.bio,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
          if (profile?.location.isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.location_on, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                const SizedBox(width: 4),
                Text(
                  profile!.location,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ],
          if (profile?.phone.isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.phone, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                const SizedBox(width: 4),
                Text(profile!.phone, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ],
          const SizedBox(height: 12),
          _buildStats(context),
        ],
      ),
    );
  }

  Widget _buildStats(BuildContext context) {
    final userService = UserService();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          FutureBuilder<int>(
            future: userService.getUserProductCount(widget.sellerId),
            builder: (c, s) =>
                _statItem(context, context.tr('products'), '${s.data ?? 0}'),
          ),
          Container(width: 1, height: 30, color: Theme.of(context).colorScheme.outlineVariant),
          FutureBuilder<int>(
            future: userService.getUserTotalSales(widget.sellerId),
            builder: (c, s) => _statItem(context, context.tr('sales'), '${s.data ?? 0}'),
          ),
        ],
      ),
    );
  }

  Widget _statItem(BuildContext context, String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => context.push(
                '${AppRoutes.chat}/${widget.sellerId}',
                extra: {'name': widget.sellerName},
              ),
              icon: Icon(Icons.message, color: Theme.of(context).colorScheme.surface),
              label: Text(context.tr('message')),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.surface,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
