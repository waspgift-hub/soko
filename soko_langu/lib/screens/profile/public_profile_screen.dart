import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../../services/user_service.dart';
import '../../services/product_service.dart';
import '../../services/rating_service.dart';
import '../../models/product_model.dart';
import '../../widgets/product_card.dart';
import '../../widgets/product_cached_image.dart';
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
import '../../widgets/rate_seller_sheet.dart';
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
  final UserService _userService = UserService();
  final ProductService _productService = ProductService();
  final FollowService _followService = FollowService();
  final RatingService _ratingService = RatingService.instance;
  late Stream<UserProfile?> _profileStream;
  late Stream<List<Product>> _productsStream;
  late Stream<int> _followerCountStream;
  late Stream<int> _followingCountStream;
  late Stream<SellerRating> _ratingStream;
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
    _initStreams();
    _flashSub = _flashSaleService.getActiveFlashSalesMap().listen((map) {
      if (mounted) setState(() => _flashSales = map);
    });
    _loadVerification();
  }

  void _initStreams() {
    _profileStream = _userService.streamProfile(widget.userId);
    _productsStream = _productService.getProductsBySeller(widget.userId);
    _followerCountStream = _followService.followerCountStream(widget.userId);
    _followingCountStream = _followService.followingCountStream(widget.userId);
    _ratingStream = _ratingService.streamSellerRating(widget.userId);
  }

  void _retry() {
    // A failed stream is terminal: a fresh subscription is the only way to
    // recover without leaving this screen.
    setState(_initStreams);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.trError(e, feature: 'shortcut', screen: 'PublicProfile'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
          stream: _profileStream,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting && !snap.hasError) {
              return const _ProfileSkeleton();
            }
            if (snap.hasError) {
              return _ProfileMessage(
                icon: Icons.cloud_off_rounded,
                title: context.tr('public_profile_load_error'),
                subtitle: context.trError(
                  snap.error!,
                  feature: 'public_profile',
                  screen: 'PublicProfile',
                ),
                onRetry: _retry,
              );
            }
            final profile = snap.data;
            if (profile == null) {
              return _ProfileMessage(
                icon: Icons.person_off_outlined,
                title: context.tr('profile_not_found'),
                subtitle: context.tr(
                  'public_profile_not_found_hint',
                  'This account may have been removed.',
                ),
              );
            }
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildHeader(context, profile)),
                SliverToBoxAdapter(child: _buildRatingSection(context)),
                SliverToBoxAdapter(child: _buildTrustSection(context)),
                SliverToBoxAdapter(child: _buildActionButtons(context)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                    child: Row(
                      children: [
                        Text(
                          context.tr('products'),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(width: 8),
                        StreamBuilder<List<Product>>(
                          stream: _productsStream,
                          builder: (context, s) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${s.data?.length ?? 0}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                StreamBuilder<List<Product>>(
                  stream: _productsStream,
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting &&
                        !snap.hasData) {
                      return const SliverToBoxAdapter(
                        child: _ProductsSkeleton(),
                      );
                    }
                    if (snap.hasError) {
                      return SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _InlineNotice(
                            icon: Icons.cloud_off_rounded,
                            title: context.trError(
                              snap.error!,
                              feature: 'seller_products',
                              screen: 'PublicProfile',
                            ),
                          ),
                        ),
                      );
                    }
                    final products = snap.data ?? const <Product>[];
                    if (products.isEmpty) {
                      return SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _InlineNotice(
                            icon: Icons.shopping_bag_outlined,
                            title: context.tr('no_products'),
                            subtitle: context.tr(
                              'seller_no_products_hint',
                              'This seller has not listed anything yet.',
                            ),
                          ),
                        ),
                      );
                    }
                    return SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        0,
                        16,
                        MediaQuery.paddingOf(context).bottom + 96,
                      ),
                      sliver: SliverGrid(
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
    final name = profile?.displayName.isNotEmpty == true
        ? profile!.displayName
        : widget.userName;
    final avatar = profile?.profileImage ?? '';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            cs.primary.withValues(alpha: cs.brightness == Brightness.dark ? 0.18 : 0.10),
            cs.surface,
          ],
        ),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.primary.withValues(alpha: 0.35), width: 2),
                ),
                child: avatar.isEmpty
                    ? Container(
                        width: 92,
                        height: 92,
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.person_outline_rounded,
                          size: 42,
                          color: cs.onSurfaceVariant,
                        ),
                      )
                    : ProductCachedImage(
                        url: avatar,
                        width: 92,
                        height: 92,
                        borderRadius: BorderRadius.circular(46),
                        errorWidget: Container(
                          width: 92,
                          height: 92,
                          color: cs.surfaceContainerHighest,
                          child: Icon(
                            Icons.person_outline_rounded,
                            size: 42,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
              ),
              if (_verification?.isBlueTickActive == true)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: cs.outlineVariant, width: 1),
                    ),
                    child: Icon(Icons.verified_rounded, size: 18, color: cs.primary),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                    color: cs.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              BlueTickBadge(sellerId: widget.userId, size: 16),
              const SizedBox(width: 6),
              BlueTickPill(verification: _verification),
            ],
          ),
          if (profile?.bio.isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text(
              profile!.bio,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 13,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (!_isMyProfile) ...[
            const SizedBox(height: 14),
            SizedBox(width: 200, child: FollowButton(targetUserId: widget.userId)),
          ],
          const SizedBox(height: 16),
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
              stream: _followerCountStream,
              label: context.tr('followers'),
              onTap: () =>
                  context.push('${AppRoutes.followers}/${widget.userId}', extra: widget.userName),
            ),
          ),
          Expanded(
            child: _statTap(
              context,
              stream: _followingCountStream,
              label: context.tr('following'),
              onTap: () =>
                  context.push('${AppRoutes.following}/${widget.userId}', extra: widget.userName),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Product>>(
              stream: _productsStream,
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
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: cs.onSurface),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildRatingSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: StreamBuilder<SellerRating>(
        stream: _ratingStream,
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
        stream: _ratingStream,
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

  Future<void> _showRateSellerDialog(BuildContext context) async {
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
    final vote = await RateSellerSheet.show(
      context,
      sellerName: widget.userName,
    );
    if (vote == null || !mounted) return;
    await _submitSellerRating(user.uid, vote.rating);
  }

  Future<void> _submitSellerRating(String raterId, int rating) async {
    // Optimistic feedback: the sheet is already dismissed, so the snackbar is
    // the only confirmation the user gets. Resolve the error through trError
    // so a failure reads in the app language instead of leaking
    // "Failed: {0}: error_generic".
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 10),
        content: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(context.tr('submitting', 'Submitting…'))),
          ],
        ),
      ),
    );
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
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(context.tr('rating_submitted'))));
    } catch (e) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(context.trError(e, feature: 'rating', screen: 'PublicProfile')),
            action: SnackBarAction(
              label: context.tr('try_again'),
              onPressed: () => _submitSellerRating(raterId, rating),
            ),
          ),
        );
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

/// Header + grid placeholder shown while the profile stream resolves.
///
/// Matches the real layout closely enough that the page does not jump when data
/// arrives. A centered spinner used to flash for a frame and then shift
/// everything down.
class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(26),
          ),
          child: Column(
            children: [
              const CircleAvatar(radius: 46, child: SizedBox()),
              const SizedBox(height: 14),
              const DsSkeleton(width: 150, height: 18),
              const SizedBox(height: 8),
              const DsSkeleton(width: 220, height: 12),
              const SizedBox(height: 16),
              const DsSkeleton(height: 56),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const DsSkeleton(height: 86),
        const SizedBox(height: 20),
        const _ProductsSkeleton(),
      ],
    );
  }
}

/// 2×2 product grid placeholder.
class _ProductsSkeleton extends StatelessWidget {
  const _ProductsSkeleton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: Responsive.gridColumns(context),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: Responsive.cardAspectRatio(context),
      ),
      itemCount: 4,
      itemBuilder: (_, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const DsSkeleton(width: 110, height: 11),
          const SizedBox(height: 6),
          const DsSkeleton(width: 70, height: 9),
        ],
      ),
    );
  }
}

/// Compact inline state used inside the profile scroll view.
///
/// `SliverFillRemaining` with a full-page spinner forced the empty state to
/// fill the viewport and pushed the seller header out of view when the grid was
/// inside a nested sliver list.
class _InlineNotice extends StatelessWidget {
  const _InlineNotice({
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 30, color: cs.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// Full-page fallback for a profile that cannot be shown at all. Rendering the
/// normal header with an empty name read as a broken seller page, so failures
/// stop here instead of leaking into ratings, follow counts and product grids.
class _ProfileMessage extends StatelessWidget {
  const _ProfileMessage({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 80),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: cs.primary),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: cs.onSurface),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, height: 1.4, color: cs.onSurfaceVariant),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(context.tr('retry')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
