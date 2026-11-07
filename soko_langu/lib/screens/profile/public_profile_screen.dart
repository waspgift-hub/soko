import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../../services/user_service.dart';
import '../../services/product_service.dart';
import '../../services/rating_service.dart';
import '../../models/product_model.dart';
import '../../widgets/product_card.dart';
import '../../widgets/google_loading.dart';
import '../../extensions/context_tr.dart';
import '../../utils/responsive.dart';
import '../../models/flash_sale_model.dart';
import '../../services/flash_sale_service.dart';
import '../../services/profile_view_service.dart';
import '../../app/routes.dart';
import '../../theme/app_colors.dart';
import '../chat/chat_navigation.dart';
import '../../widgets/blue_tick_badge.dart';
import '../../widgets/ds/ds.dart';
import '../../models/seller_verification.dart';
import '../../services/seller_verification_service.dart';
import '../../services/share_service.dart';
import '../../services/shortcut_service.dart';
import '../../widgets/social/follow_button.dart';
import '../../services/follow_service.dart';
import '../../utils/network_error.dart';
import 'package:provider/provider.dart';

class PublicProfileScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const PublicProfileScreen({super.key, required this.userId, this.userName = ''});

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  bool _isMyProfile = false;
  final FlashSaleService _flashSaleService = FlashSaleService();
  Map<String, FlashSale> _flashSales = {};
  StreamSubscription? _flashSub;

  /// Trusted verification snapshot for the seller on this page. Subscribing
  /// means a revocation removes the badge without a restart.
  SellerVerification? _verification;

  @override
  void initState() {
    super.initState();
    _isMyProfile = FirebaseAuth.instance.currentUser?.uid == widget.userId;
    if (!_isMyProfile) {
      ProfileViewService().trackView(widget.userId, widget.userName);
    }
    _flashSub = _flashSaleService.getActiveFlashSalesMap().listen((map) {
      if (mounted) setState(() => _flashSales = map);
    });
    _loadVerification();
  }

  Future<void> _loadVerification() async {
    final v = await context.read<SellerVerificationService>().resolve(widget.userId);
    if (!mounted) return;
    setState(() => _verification = v);
  }

  @override
  void dispose() {
    _flashSub?.cancel();
    super.dispose();
  }

  void _chatWithSeller() {
    ChatNavigation.openSellerChat(context, widget.userId, widget.userName);
  }

  Future<void> _addProfileShortcut() async {
    try {
      final snap = await UserService().getProfile(widget.userId);
      final iconUrl = (snap?.profileImage ?? '').trim();
      final name = (snap?.displayName ?? widget.userName).trim();
      final ok = await pinProfileShortcut(
        userId: widget.userId,
        displayName: name.isEmpty ? 'Soko Vibe' : name,
        iconUrl: iconUrl.isEmpty ? null : iconUrl,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? context.tr('shortcut_added')
                : context.tr(
                    'shortcut_not_supported',
                    'Shortcut haijaunganishwa kwenye skrini ya nyumbani',
                  ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(translateError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final productService = ProductService();
    final userService = UserService();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.userName),
        actions: [
          IconButton(
            tooltip: context.tr('share'),
            icon: const Icon(Icons.share_outlined),
            onPressed: () async {
              // Prefer username if available from profile stream; fallback to uid
              final snap = await UserService().getProfile(widget.userId);
              final uname = snap?.username ?? '';
              if (uname.isNotEmpty) {
                await ShareService.instance.shareProfile(
                  userId: widget.userId,
                  displayName: widget.userName,
                  username: uname,
                );
              } else {
                await ShareService.instance.shareSeller(
                  sellerId: widget.userId,
                  sellerName: widget.userName.isNotEmpty ? widget.userName : 'Muuzaji',
                );
              }
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              if (value == 'shortcut') await _addProfileShortcut();
              if (value == 'report') {
                context.push(
                  AppRoutes.report,
                  extra: {'reportedUserId': widget.userId, 'reportedUserName': widget.userName},
                );
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'shortcut',
                child: ListTile(
                  leading: const Icon(Icons.add_to_home_screen),
                  title: Text(context.tr('add_shortcut', 'Add Shortcut')),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (!_isMyProfile)
                PopupMenuItem(
                  value: 'report',
                  child: ListTile(
                    leading: Icon(
                      Icons.flag_outlined,
                      color: Theme.of(context).colorScheme.error.withValues(alpha: 0.7),
                    ),
                    title: Text(context.tr('report_user')),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
            ],
          ),
          if (!_isMyProfile)
            IconButton(
              tooltip: context.tr('send_message'),
              icon: Icon(Icons.chat, color: Theme.of(context).colorScheme.whatsappGreen),
              onPressed: _chatWithSeller,
            ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<UserProfile?>(
          stream: userService.streamProfile(widget.userId),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) return const GoogleLoadingPage();
            final profile = snap.data;
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildHeader(context, profile)),
                SliverToBoxAdapter(child: _buildRatingSection(context)),
                SliverToBoxAdapter(child: _buildTrustSection(context)),
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
                  stream: productService.getProductsBySeller(widget.userId),
                  builder: (context, snap) {
                    if (!snap.hasData) return const SliverFillRemaining(child: GoogleLoadingPage());
                    final products = snap.data!;
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
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return SliverMainAxisGroup(
                      slivers: [
                        SliverGrid(
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
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
                            addAutomaticKeepAlives: false,
                          ),
                        ),

                      ],
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
    final cs = Theme.of(context).colorScheme;
    final name = profile?.displayName.isNotEmpty == true ? profile!.displayName : widget.userName;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        children: [
          CircleAvatar(
            radius: 50,
            backgroundColor: cs.surfaceContainerHighest,
            backgroundImage: profile?.profileImage.isNotEmpty == true
                ? NetworkImage(profile!.profileImage)
                : null,
            child: profile?.profileImage.isEmpty != false
                ? Icon(Icons.person_outline_rounded, size: 44, color: cs.onSurfaceVariant)
                : null,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  name,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: cs.onSurface),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              BlueTickBadge(sellerId: widget.userId, size: 16),
              const SizedBox(width: 6),
              BlueTickPill(verification: _verification),
            ],
          ),
          if (profile?.bio.isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text(
              profile!.bio,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
          if (!_isMyProfile) ...[
            const SizedBox(height: 12),
            SizedBox(width: 180, child: FollowButton(targetUserId: widget.userId)),
          ],
          const SizedBox(height: 12),
          _buildStats(context, profile),
        ],
      ),
    );
  }

  Widget _buildStats(BuildContext context, UserProfile? profile) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _statTap(
              context,
              stream: FollowService().followerCountStream(widget.userId),
              label: context.tr('followers'),
              onTap: () =>
                  context.push('${AppRoutes.followers}/${widget.userId}', extra: widget.userName),
            ),
          ),
          Expanded(
            child: _statTap(
              context,
              stream: FollowService().followingCountStream(widget.userId),
              label: context.tr('following'),
              onTap: () =>
                  context.push('${AppRoutes.following}/${widget.userId}', extra: widget.userName),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Product>>(
              stream: ProductService().getProductsBySeller(widget.userId),
              builder: (context, snap) =>
                  _statValue(context, '${snap.data?.length ?? 0}', context.tr('products')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statTap(
    BuildContext context, {
    required Stream<int> stream,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: StreamBuilder<int>(
        stream: stream,
        builder: (context, snap) => _statValue(context, '${snap.data ?? 0}', label),
      ),
    );
  }

  Widget _statValue(BuildContext context, String value, String label) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: cs.onSurface),
        ),
        Text(label, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
      ],
    );
  }

  Widget _buildRatingSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: StreamBuilder<SellerRating>(
        stream: RatingService.instance.streamSellerRating(widget.userId),
        builder: (context, snap) {
          final rating = snap.data;
          if (rating == null || rating.totalReviews == 0) {
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.primary.withValues(alpha: 0.1)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.star_outline, size: 18, color: cs.primary.withValues(alpha: 0.5)),
                  const SizedBox(width: 6),
                  Text(
                    context.tr('no_ratings_yet'),
                    style: TextStyle(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            );
          }
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.primary.withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                Column(
                  children: [
                    Text(
                      rating.averageRating.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: cs.primary,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(5, (i) {
                        final filled = i < rating.averageRating.round();
                        return Icon(
                          filled ? Icons.star : Icons.star_border,
                          color: cs.primary,
                          size: 16,
                        );
                      }),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '(${rating.totalReviews})',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    children: [
                      _ratingRow(cs, 5, rating.fiveStar, rating.totalReviews),
                      _ratingRow(cs, 4, rating.fourStar, rating.totalReviews),
                      _ratingRow(cs, 3, rating.threeStar, rating.totalReviews),
                      _ratingRow(cs, 2, rating.twoStar, rating.totalReviews),
                      _ratingRow(cs, 1, rating.oneStar, rating.totalReviews),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _ratingRow(ColorScheme cs, int star, int count, int total) {
    final pct = total > 0 ? count / total : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text('$star', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 4,
                backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                color: cs.primary,
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 24,
            child: Text('$count', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }

  Widget _buildTrustSection(BuildContext context) {
    // ignore: unused_local_variable
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: StreamBuilder<SellerRating>(
        stream: RatingService.instance.streamSellerRating(widget.userId),
        builder: (context, snap) {
          final rating = snap.data;
          if (rating == null || rating.totalReviews == 0) {
            return const SizedBox.shrink();
          }
          return _buildTrustScore(rating.averageRating, rating.totalReviews);
        },
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    if (_isMyProfile) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            Expanded(
              child: OneUIButton(
                label: context.tr('edit_profile', 'Hariri Wasifu'),
                icon: Icons.edit_outlined,
                primary: false,
                onPressed: () => context.push(AppRoutes.editProfile),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OneUIButton(
                label: context.tr('my_ads', 'Matangazo Yangu'),
                icon: Icons.inventory_2_outlined,
                primary: true,
                onPressed: () => context.push(AppRoutes.myAds),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: OneUIButton(
              label: context.tr('chat'),
              icon: Icons.chat_bubble_outline_rounded,
              primary: true,
              onPressed: _chatWithSeller,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OneUIButton(
              label: context.tr('rate_seller'),
              icon: Icons.thumb_up_alt_outlined,
              primary: false,
              onPressed: () => _showRateSellerDialog(context),
            ),
          ),
        ],
      ),
    );
  }

  void _showRateSellerDialog(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('please_log_in_first'))));
      return;
    }
    if (user.uid == widget.userId) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('cannot_rate_self'))));
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('rate_seller')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.tr('rate_seller_trust_prompt')),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  icon: Icon(Icons.thumb_down_alt, color: Theme.of(ctx).colorScheme.onError),
                  label: Text(context.tr('not_trustworthy')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error,
                    foregroundColor: Theme.of(ctx).colorScheme.onError,
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _submitSellerRating(user.uid, 1);
                  },
                ),
                ElevatedButton.icon(
                  icon: Icon(Icons.thumb_up_alt, color: Theme.of(ctx).colorScheme.onPrimary),
                  label: Text(context.tr('trustworthy')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.primary,
                    foregroundColor: Theme.of(ctx).colorScheme.onPrimary,
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _submitSellerRating(user.uid, 5);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitSellerRating(String raterId, int rating) async {
    try {
      final userProfile = await UserService().getProfile(raterId);
      final userName = userProfile?.displayName ?? raterId;
      await RatingService().submitReview(
        productId: 'seller_${widget.userId}',
        sellerId: widget.userId,
        userId: raterId,
        userName: userName,
        rating: rating.toDouble(),
        comment: '',
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.tr('rating_submitted'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${context.tr('imeshindwa')}: $e')));
      }
    }
  }

  Widget _buildTrustScore(double avgRating, int totalReviews) {
    final cs = Theme.of(context).colorScheme;
    final trustPct = totalReviews > 0 ? ((avgRating / 5) * 100).round() : 0;
    Color trustColor;
    IconData trustIcon;
    if (trustPct >= 80) {
      trustColor = cs.primary;
      trustIcon = Icons.verified;
    } else if (trustPct >= 50) {
      trustColor = cs.tertiary;
      trustIcon = Icons.hourglass_empty;
    } else if (trustPct > 0) {
      trustColor = cs.error;
      trustIcon = Icons.warning_amber;
    } else {
      trustColor = cs.onSurfaceVariant.withValues(alpha: 0.5);
      trustIcon = Icons.help_outline;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(trustIcon, size: 16, color: trustColor),
          const SizedBox(width: 6),
          Text(
            trustPct > 0
                ? '${context.tr('trust_score')}: $trustPct% ($totalReviews ${context.tr('reviews').toLowerCase()})'
                : context.tr('no_ratings_yet'),
            style: TextStyle(fontSize: 12, color: trustColor, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
