import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
import '../../theme/app_colors.dart';
import '../../utils/phone_utils.dart';
import '../../utils/responsive.dart';
import '../../utils/chat_utils.dart';

class PublicProfileScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const PublicProfileScreen({
    super.key,
    required this.userId,
    this.userName = '',
  });

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  bool _isMyProfile = false;
  final FlashSaleService _flashSaleService = FlashSaleService();
  Map<String, FlashSale> _flashSales = {};
  StreamSubscription? _flashSub;
  UserProfile? _profile;

  @override
  void initState() {
    super.initState();
    _isMyProfile = FirebaseAuth.instance.currentUser?.uid == widget.userId;
    _flashSub = _flashSaleService.getActiveFlashSalesMap().listen((map) {
      if (mounted) setState(() => _flashSales = map);
    });
  }

  @override
  void dispose() {
    _flashSub?.cancel();
    super.dispose();
  }

  void _chatWithSeller() {
    showChatOptions(
      context: context,
      sellerId: widget.userId,
      sellerName: widget.userName,
      phone: _profile?.phone,
    );
  }

  @override
  Widget build(BuildContext context) {
    final productService = ProductService();
    final userService = UserService();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.userName),
        actions: [
          if (!_isMyProfile) ...[
            IconButton(
              icon: Icon(
                Icons.chat,
                color: Theme.of(context).colorScheme.whatsappGreen,
              ),
              onPressed: _chatWithSeller,
            ),
            IconButton(
              icon: Icon(
                Icons.flag_outlined,
                color: Theme.of(
                  context,
                ).colorScheme.error.withValues(alpha: 0.7),
              ),
              onPressed: () => context.push(
                AppRoutes.report,
                extra: {
                  'reportedUserId': widget.userId,
                  'reportedUserName': widget.userName,
                },
              ),
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<UserProfile?>(
          stream: userService.streamProfile(widget.userId),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting)
              return const GoogleLoadingPage();
            final profile = snap.data;
            if (profile != null) _profile = profile;
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
                    if (!snap.hasData)
                      return const SliverFillRemaining(
                        child: GoogleLoadingPage(),
                      );
                    final products = snap.data!
                        .where((p) => p.sellerId == widget.userId)
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
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                context.tr('no_products'),
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
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

  Widget _buildHeader(BuildContext context, UserProfile? profile) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
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
                                : widget.userName)[0]
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
                child: StreamBuilder<bool>(
                  stream: Stream.value(false),
                  builder: (context, snap) {
                    final online = snap.data ?? false;
                    return Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: online
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.surface,
                          width: 2,
                        ),
                      ),
                    );
                  },
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
                    : widget.userName,
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
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (profile?.location.isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.location_on,
                  size: 16,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    profile!.location,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (profile?.phone.isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.phone,
                  size: 16,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    PhoneUtils.formatForDisplay(profile!.phone),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
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
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _statItem(
            context,
            context.tr('products'),
            StreamBuilder<List<Product>>(
              stream: ProductService().getProducts(),
              builder: (context, snap) {
                final count =
                    snap.data
                        ?.where((p) => p.sellerId == widget.userId)
                        .length ??
                    0;
                return Text(
                  '$count',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _statItem(BuildContext context, String label, Widget valueWidget) {
    return Column(
      children: [
        valueWidget,
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
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
              onPressed: _chatWithSeller,
              icon: Icon(
                Icons.chat,
                color: Theme.of(context).colorScheme.surface,
              ),
              label: Text('Chat'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.whatsappGreen,
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
