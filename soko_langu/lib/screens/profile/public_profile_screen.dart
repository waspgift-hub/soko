import 'package:flutter/material.dart';
import '../../models/product_model.dart';
import '../../services/product_service.dart';
import '../../services/user_service.dart';
import '../../extensions/context_tr.dart';
import '../home/product_detail.dart';
import '../chat/chat_page.dart';
import '../../widgets/product_card.dart';
import '../../widgets/verified_badge.dart';
import '../../main.dart';

class PublicProfileScreen extends StatelessWidget {
  final String userId;
  final String userName;

  const PublicProfileScreen({
    super.key,
    required this.userId,
    this.userName = '',
  });

  @override
  Widget build(BuildContext context) {
    final productService = ProductService();
    final userService = UserService();

    return Scaffold(
      appBar: AppBar(
        title: Text(userName),
        actions: [
          IconButton(
            icon: const Icon(Icons.message, color: Colors.green),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ChatPage(receiverId: userId, receiverName: userName),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<UserProfile?>(
          stream: userService.streamProfile(userId),
          builder: (context, snap) {
            final profile = snap.data;
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildHeader(context, profile)),
                SliverToBoxAdapter(child: _buildActionButtons(context)),
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
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const SliverFillRemaining(
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final products = snap.data!
                        .where((p) => p.sellerId == userId)
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
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                context.tr('no_products'),
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.7,
                          ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => ProductCard(
                          product: products[index],
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  ProductDetailPage(product: products[index]),
                            ),
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

  Color _parseColor(String hex) {
    if (hex.isEmpty) return Colors.green;
    hex = hex.replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }

  Widget _buildStorefront(BuildContext context, UserProfile? profile) {
    final hasStorefront =
        profile != null &&
        profile.isPaid &&
        (profile.shopBanner.isNotEmpty || profile.shopBannerColor.isNotEmpty);
    if (!hasStorefront) return const SizedBox.shrink();

    final bannerColor = profile.shopBannerColor.isNotEmpty
        ? _parseColor(profile.shopBannerColor)
        : Colors.green;
    final accent = profile.shopAccentColor.isNotEmpty
        ? _parseColor(profile.shopAccentColor)
        : Colors.green;

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
            colors: [Colors.transparent, Colors.black38],
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
                profile.isSilver
                    ? context.tr('shop_silver_banner')
                    : context.tr('shop_premium_banner'),
                style: const TextStyle(
                  color: Colors.white,
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
          StreamBuilder<bool>(
            stream: presenceService.isOnline(userId),
            builder: (context, snap) {
              final online = snap.data ?? false;
              return Stack(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.green,
                    backgroundImage: profile?.profileImage.isNotEmpty == true
                        ? NetworkImage(profile!.profileImage)
                        : null,
                    child: profile?.profileImage.isEmpty != false
                        ? Text(
                            (profile?.displayName.isNotEmpty == true
                                    ? profile!.displayName
                                    : userName)[0]
                                .toUpperCase(),
                            style: const TextStyle(
                              fontSize: 40,
                              color: Colors.white,
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
                        color: online ? Colors.green : Colors.grey,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                profile?.displayName.isNotEmpty == true
                    ? profile!.displayName
                    : userName,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              VerifiedBadge(
                tier: profile?.accountTier,
                isAdmin: profile?.email == 'admin@soko-langu.com',
              ),
            ],
          ),
          if (profile?.bio.isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text(
              profile!.bio,
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
          if (profile?.location.isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.location_on, size: 16, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Text(
                  profile!.location,
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          ],
          if (profile?.phone.isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.phone, size: 16, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Text(profile!.phone, style: TextStyle(color: Colors.grey[600])),
              ],
            ),
          ],
          const SizedBox(height: 12),
          _buildStats(context, profile),
        ],
      ),
    );
  }

  Widget _buildStats(BuildContext context, UserProfile? profile) {
    final userService = UserService();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          FutureBuilder<int>(
            future: userService.getUserProductCount(userId),
            builder: (context, snap) =>
                _statItem(context, context.tr('products'), '${snap.data ?? 0}'),
          ),
          Container(width: 1, height: 30, color: Colors.grey[200]),
          FutureBuilder<int>(
            future: userService.getUserTotalSales(userId),
            builder: (context, snap) =>
                _statItem(context, context.tr('sales'), '${snap.data ?? 0}'),
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
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ChatPage(receiverId: userId, receiverName: userName),
                  ),
                );
              },
              icon: const Icon(Icons.message, color: Colors.white),
              label: Text(context.tr('message')),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
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
