import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../../models/product_model.dart';
import '../../services/product_service.dart';
import '../../services/user_service.dart';
import '../../services/follow_service.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/product_card.dart';
import '../../widgets/verified_badge.dart';
import '../../main.dart';
import '../../app/routes.dart';

class PublicProfileScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const PublicProfileScreen({super.key, required this.userId, this.userName = ''});

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  final FollowService _followService = FollowService();
  bool _isMyProfile = false;

  @override
  void initState() {
    super.initState();
    _isMyProfile = FirebaseAuth.instance.currentUser?.uid == widget.userId;
  }

  @override
  Widget build(BuildContext context) {
    final productService = ProductService();
    final userService = UserService();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.userName),
        actions: [
          if (!_isMyProfile)
            IconButton(
              icon: const Icon(Icons.message, color: Colors.green),
              onPressed: () => context.push('${AppRoutes.chat}/${widget.userId}', extra: {'name': widget.userName}),
            ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<UserProfile?>(
          stream: userService.streamProfile(widget.userId),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            final profile = snap.data;
            return CustomScrollView(slivers: [
              SliverToBoxAdapter(child: _buildHeader(context, profile)),
              if (!_isMyProfile) SliverToBoxAdapter(child: _buildFollowButton()),
              SliverToBoxAdapter(child: _buildActionButtons(context)),
              SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), child: Text(context.tr('products'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)))),
              StreamBuilder<List<Product>>(
                stream: productService.getProducts(),
                builder: (context, snap) {
                  if (!snap.hasData) return const SliverFillRemaining(child: Center(child: CircularProgressIndicator()));
                  final products = snap.data!.where((p) => p.sellerId == widget.userId).toList();
                  if (products.isEmpty) {
                    return SliverFillRemaining(child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.shopping_bag_outlined, size: 64, color: Colors.grey[400]), const SizedBox(height: 16), Text(context.tr('no_products'), style: TextStyle(color: Colors.grey[600]))])));
                  }
                  return SliverGrid(gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.7), delegate: SliverChildBuilderDelegate((context, index) => ProductCard(product: products[index], onTap: () => context.push('${AppRoutes.productDetail}/${products[index].id}', extra: products[index])), childCount: products.length));
                },
              ),
            ]);
          },
        ),
      ),
    );
  }

  Widget _buildFollowButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: StreamBuilder<bool>(
        stream: _followService.isFollowingStream(widget.userId),
        builder: (context, snap) {
          final following = snap.data ?? false;
          return SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                try {
                  if (following) {
                    await _followService.unfollow(widget.userId);
                  } else {
                    await _followService.follow(widget.userId);
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                  }
                }
              },
              style: OutlinedButton.styleFrom(
                backgroundColor: following ? Colors.green : null,
                foregroundColor: following ? Colors.white : Colors.green,
                side: BorderSide(color: following ? Colors.green : Colors.green),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: Icon(following ? Icons.check : Icons.person_add),
              label: Text(following ? context.tr('following') : context.tr('follow')),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context, UserProfile? profile) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 50,
                backgroundColor: Colors.green,
                backgroundImage: profile?.profileImage.isNotEmpty == true ? NetworkImage(profile!.profileImage) : null,
                child: profile?.profileImage.isEmpty != false
                    ? Text((profile?.displayName.isNotEmpty == true ? profile!.displayName : widget.userName)[0].toUpperCase(), style: const TextStyle(fontSize: 40, color: Colors.white))
                    : null,
              ),
              Positioned(
                right: 4, bottom: 4,
                child: StreamBuilder<bool>(
                  stream: presenceService.isOnline(widget.userId),
                  builder: (context, snap) {
                    final online = snap.data ?? false;
                    return Container(width: 16, height: 16, decoration: BoxDecoration(color: online ? Colors.green : Colors.grey, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)));
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(profile?.displayName.isNotEmpty == true ? profile!.displayName : widget.userName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            VerifiedBadge(tier: profile?.accountTier, isAdmin: profile?.email == 'admin@soko-langu.com'),
          ]),
          if (profile?.bio.isNotEmpty == true) ...[const SizedBox(height: 4), Text(profile!.bio, style: TextStyle(color: Colors.grey[600], fontSize: 14), textAlign: TextAlign.center)],
          if (profile?.location.isNotEmpty == true) ...[const SizedBox(height: 4), Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.location_on, size: 16, color: Colors.grey[500]), const SizedBox(width: 4), Text(profile!.location, style: TextStyle(color: Colors.grey[600]))])],
          if (profile?.phone.isNotEmpty == true) ...[const SizedBox(height: 4), Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.phone, size: 16, color: Colors.grey[500]), const SizedBox(width: 4), Text(profile!.phone, style: TextStyle(color: Colors.grey[600]))])],
          const SizedBox(height: 12),
          _buildStats(context, profile),
        ],
      ),
    );
  }

  Widget _buildStats(BuildContext context, UserProfile? profile) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5), width: 1.5)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _statItem(context, context.tr('products'), StreamBuilder<int>(stream: _followService.followingCount(widget.userId), builder: (context, snap) => Text('${snap.data ?? 0}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)))),
          Container(width: 1, height: 30, color: Theme.of(context).colorScheme.outlineVariant),
          _statItem(context, context.tr('followers'), StreamBuilder<int>(stream: _followService.followersCount(widget.userId), builder: (context, snap) => Text('${snap.data ?? 0}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)))),
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
      child: Row(children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => context.push('${AppRoutes.chat}/${widget.userId}', extra: {'name': widget.userName}),
            icon: const Icon(Icons.message, color: Colors.white),
            label: Text(context.tr('message')),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
        ),
      ]),
    );
  }
}
