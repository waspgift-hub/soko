import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/product_model.dart';
import '../../services/product_service.dart';
import '../../services/user_service.dart';
import '../../services/whatsapp_service.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/product_card.dart';
import '../../widgets/verified_badge.dart';
import '../../app/routes.dart';

class PublicProfileScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const PublicProfileScreen({super.key, required this.userId, this.userName = ''});

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  String _sellerPhone = '';

  @override
  Widget build(BuildContext context) {
    final productService = ProductService();
    final userService = UserService();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.userName),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat, color: Color(0xFF25D366)),
            tooltip: 'WhatsApp',
            onPressed: () => _openWhatsApp(),
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<UserProfile?>(
          stream: userService.streamProfile(widget.userId),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final profile = snap.data;
            
            if (profile != null && profile.phone.isNotEmpty) {
              _sellerPhone = profile.phone;
            }

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildHeader(context, profile)),
                SliverToBoxAdapter(child: _buildActionButtons(context)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      context.tr('products'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                    final products = snap.data!.where((p) => p.sellerId == widget.userId).toList();
                    if (products.isEmpty) {
                      return SliverFillRemaining(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.shopping_bag_outlined, size: 64, color: Colors.grey[400]),
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
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.7,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => ProductCard(
                          product: products[index],
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

  Widget _buildHeader(BuildContext context, UserProfile? profile) {
    final displayName = profile?.displayName.isNotEmpty == true 
        ? profile!.displayName 
        : widget.userName;

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 50,
                backgroundColor: const Color(0xFF2D6A4F),
                backgroundImage: profile?.profileImage.isNotEmpty == true 
                    ? NetworkImage(profile!.profileImage) 
                    : null,
                child: profile?.profileImage.isEmpty != false
                    ? Text(
                        displayName[0].toUpperCase(),
                        style: const TextStyle(fontSize: 40, color: Colors.white),
                      )
                    : null,
              ),
              if (profile?.accountTier == 'premium')
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.amber,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.star, color: Colors.white, size: 16),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                displayName,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
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
                Text(profile!.location, style: TextStyle(color: Colors.grey[600])),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _statItem(
            context,
            context.tr('products'),
            StreamBuilder<int>(
              stream: ProductService().getProducts().map(
                (p) => p.where((x) => x.sellerId == widget.userId).length,
              ),
              builder: (context, snap) => Text(
                '${snap.data ?? 0}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statItem(BuildContext context, String label, Widget valueWidget) {
    return Column(children: [valueWidget, Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13))]);
  }

  Widget _buildActionButtons(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _openWhatsApp(),
              icon: const Icon(Icons.chat, color: Colors.white),
              label: const Text('WhatsApp'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
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

  Future<void> _openWhatsApp() async {
    if (_sellerPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Namba ya simu ya muuzaji haipatikani'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final displayName = widget.userName.isNotEmpty ? widget.userName : 'Muuzaji';
    final message = WhatsAppService.generateProfileInquiryMessage(
      sellerName: displayName,
    );

    final success = await WhatsAppService().openWhatsApp(
      phoneNumber: _sellerPhone,
      message: message,
      onError: () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Imeshindwa kufungua WhatsApp'),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
      onFallback: () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('WhatsApp haipo, imefungua tovuti'),
            ),
          );
        }
      },
    );

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tafadhali install WhatsApp kwanza'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }
}
