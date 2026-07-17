import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';
import 'package:go_router/go_router.dart';
import '../../models/product_model.dart';
import '../../models/category_model.dart';
import '../../services/wishlist_service.dart';
import '../../services/category_service.dart';
import '../../services/localization_service.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../widgets/ad_banner.dart';
import '../../widgets/google_loading.dart';
import '../../widgets/review_section.dart';
import '../../widgets/comment_section.dart';
import '../../widgets/verified_badge.dart';
import '../../widgets/premium_widgets.dart';
import '../../services/product_service.dart';
import '../../services/user_service.dart';
import '../../services/analytics_service.dart';
import '../../services/flash_sale_service.dart';
import '../../models/flash_sale_model.dart';
import '../../theme/app_colors.dart';
import '../../services/notification_service.dart';
import '../chat/chat_navigation.dart';

Color? _hexToColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  try {
    final clean = hex.replaceFirst('#', '');
    if (clean.length != 6) return null;
    return Color(int.parse('FF$clean', radix: 16));
  } catch (_) {
    return null;
  }
}

class ProductDetailPage extends StatefulWidget {
  final Product product;

  const ProductDetailPage({super.key, required this.product});

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  final WishlistService _wishlistService = WishlistService();
  final UserService _userService = UserService();
  final FlashSaleService _flashSaleService = FlashSaleService();
  bool _isFav = false;
  String? _selectedVariantId;
  final PageController _imageController = PageController();
  int _currentImageIndex = 0;
  final Map<int, double> _imageRatios = {};
  UserProfile? _sellerProfile;
  bool _processing = false;
  FlashSale? _flashSale;
  Timer? _flashTimer;
  StreamSubscription<FlashSale?>? _flashStreamSub;
  bool _viewIncremented = false;

  @override
  void initState() {
    super.initState();
    _checkFav();
    _loadSellerProfile();
    _loadFlashSale();
    if (!_viewIncremented) {
      _viewIncremented = true;
      ProductService().incrementViewCount(widget.product.id);
      AnalyticsService().trackProductView(widget.product.id);
    }
  }

  String _lastDisplay = '';

  void _loadFlashSale() {
    _flashStreamSub = _flashSaleService
        .streamFlashSaleByProductId(widget.product.id)
        .listen((sale) {
          if (!mounted) return;
          setState(() {
            _flashSale = sale;
            _lastDisplay = '';
          });
          if (sale != null) {
            _flashTimer?.cancel();
            _flashTimer = Timer.periodic(const Duration(seconds: 1), (_) {
              if (!mounted) return;
              final display = sale.remainingTime.isNegative
                  ? ''
                  : _fmtDuration(sale.remainingTime);
              if (display != _lastDisplay) {
                _lastDisplay = display;
                setState(() {});
              }
            });
          } else {
            _flashTimer?.cancel();
          }
        });
  }

  Future<void> _loadSellerProfile() async {
    final profile = await _userService.getProfile(widget.product.sellerId);
    if (mounted) setState(() => _sellerProfile = profile);
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    _flashStreamSub?.cancel();
    _imageController.dispose();
    super.dispose();
  }

  Future<void> _checkFav() async {
    final fav = await _wishlistService.isFavorite(widget.product.id);
    if (mounted) setState(() => _isFav = fav);
  }

  void _resolveImageSize(int index, ImageProvider provider) {
    if (_imageRatios.containsKey(index)) return;
    final stream = provider.resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener((info, _) {
      if (!mounted) return;
      final image = info.image;
      final ratio = image.width / image.height;
      if (ratio > 0 && _imageRatios[index] != ratio) {
        setState(() => _imageRatios[index] = ratio);
      }
    });
    stream.addListener(listener);
  }

  Future<void> _toggleFav() async {
    final wasFav = _isFav;
    await _wishlistService.toggle(widget.product.id);
    setState(() => _isFav = !wasFav);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isFav
                ? context.tr('added_to_wishlist')
                : context.tr('removed_from_wishlist'),
          ),
        ),
      );
    }
    // Notify seller when product is liked
    if (!wasFav) {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null && currentUser.uid != widget.product.sellerId) {
        final userName =
            currentUser.displayName ?? currentUser.email ?? 'Mtumiaji';
        await NotificationService().sendNotification(
          userId: widget.product.sellerId,
          title: '$userName amependa bidhaa yako',
          body: widget.product.name,
          data: {
            'type': 'wishlist',
            'productId': widget.product.id,
            'productName': widget.product.name,
          },
        );
      }
    }
  }

  void _shareProduct(Product product) {
    final text =
        "${product.name}\n"
        "Price: ${LocalizationService.supportedCurrencies[product.currency]?['symbol'] ?? 'TSh'} ${product.price.toStringAsFixed(0)}\n"
        "${context.tr('check_out_on')}";
    SharePlus.instance.share(ShareParams(text: text));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final currentUser = FirebaseAuth.instance.currentUser;
    final product = widget.product;
    final sellerId = product.sellerId;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('product_detail')),
        actions: [
          IconButton(
            icon: Icon(Icons.share, color: cs.primary),
            onPressed: () => _shareProduct(product),
          ),
          IconButton(
            icon: Icon(
              _isFav ? Icons.favorite : Icons.favorite_border,
              color: _isFav ? cs.error : null,
            ),
            onPressed: _toggleFav,
          ),
          if (currentUser != null && currentUser.uid != sellerId)
            IconButton(
              icon: Icon(
                Icons.flag_outlined,
                color: cs.error.withValues(alpha: 0.7),
              ),
              onPressed: () => context.push(
                AppRoutes.report,
                extra: {
                  'reportedUserId': sellerId,
                  'reportedUserName': product.sellerName,
                  'productId': product.id,
                  'productName': product.name,
                },
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom + 20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      final ratio = _imageRatios[_currentImageIndex];
                      final height = ratio != null
                          ? (width / ratio).clamp(200.0, width * 1.2)
                          : width * 0.6;

                      return SizedBox(
                        width: width,
                        height: height,
                        child: product.images.isNotEmpty
                            ? PageView.builder(
                                controller: _imageController,
                                itemCount: product.images.length,
                                onPageChanged: (index) {
                                  setState(() => _currentImageIndex = index);
                                },
                                itemBuilder: (context, index) {
                                  return GestureDetector(
                                    onTap: () => _showFullScreenImage(
                                      context,
                                      product.images,
                                      index,
                                    ),
                                    child: CachedNetworkImage(
                                      imageUrl: product.images[index],
                                      fit: BoxFit.contain,
                                      imageBuilder: (context, imageProvider) {
                                        _resolveImageSize(index, imageProvider);
                                        return Image(
                                          image: imageProvider,
                                          fit: BoxFit.contain,
                                        );
                                      },
                                      placeholder: (context, url) => Container(
                                        color: cs.surfaceContainerLow,
                                        child: const Center(
                                          child: GoogleLoading(
                                            size: 24,
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                      errorWidget:
                                          (context, error, stackTrace) =>
                                              Container(
                                                color:
                                                    cs.surfaceContainerHighest,
                                                child: const Icon(
                                                  Icons.image,
                                                  size: 50,
                                                ),
                                              ),
                                    ),
                                  );
                                },
                              )
                            : const SizedBox(),
                      );
                    },
                  ),
                  if (product.images.length > 1)
                    Positioned(
                      bottom: 12,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          product.images.length,
                          (index) => Container(
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: _currentImageIndex == index ? 10 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _currentImageIndex == index
                                  ? cs.surface
                                  : cs.surface.withValues(alpha: 0.5),
                              border: Border.all(
                                color: cs.onSurface.withValues(alpha: 0.2),
                                width: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (product.images.isNotEmpty)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: cs.onSurface.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_currentImageIndex + 1}/${product.images.length}',
                          style: TextStyle(
                            color: cs.surface,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (product.images.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.photo_library,
                        size: 16,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        context
                            .tr('images_count')
                            .replaceAll(
                              '{0}',
                              product.images.length.toString(),
                            ),
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_flashSale != null) ...[
                      Row(
                        children: [
                          Text(
                            context.formatPrice(_flashSale!.salePrice),
                            style: TextStyle(
                              color: cs.error,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            context.formatPrice(_flashSale!.originalPrice),
                            style: TextStyle(
                              decoration: TextDecoration.lineThrough,
                              color: cs.onSurface.withValues(alpha: 0.4),
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: cs.error,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '-${_flashSale!.discountPercent.toStringAsFixed(0)}%',
                              style: TextStyle(
                                color: cs.surface,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _flashSale!.remainingTime.isNegative
                            ? context.tr('expired')
                            : context
                                  .tr('flash_sale_ends_in')
                                  .replaceAll(
                                    '{0}',
                                    _fmtDuration(_flashSale!.remainingTime),
                                  ),
                        style: TextStyle(
                          color: cs.error,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '${context.tr('ends')} ${_fmtDate(_flashSale!.endTime)}',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ] else ...[
                      Text(
                        context.formatPrice(product.price),
                        style: TextStyle(
                          color: cs.secondary,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_selectedVariantId != null)
                        Text(
                          "${context.tr('with_variant')} ${context.formatPrice(_getEffectivePrice())}",
                          style: TextStyle(color: cs.primary, fontSize: 14),
                        ),
                    ],
                    if (product.rating > 0) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.star, color: cs.tertiary, size: 20),
                          const SizedBox(width: 4),
                          Text(
                            "${product.rating.toStringAsFixed(1)} (${product.reviewCount} ${context.tr('reviews_count')})",
                            style: TextStyle(
                              color: cs.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "${product.soldCount} ${context.tr('sold')}",
                            style: TextStyle(
                              color: cs.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      context.tr('description'),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      product.description,
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.6),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      context.tr('details'),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildDetailRow(
                      context.tr('category'),
                      _getCategoryDisplay(product.category),
                    ),
                    if (product.brand != null)
                      _buildDetailRow(context.tr('brand'), product.brand!),
                    _buildDetailRow(context.tr('condition'), product.condition),
                    _buildDetailRow(context.tr('location'), product.location),
                    _buildDetailRow(
                      context.tr('stock'),
                      "${product.stock} ${context.tr('units')}",
                    ),
                    if (product.isWholesale)
                      _buildDetailRow(
                        context.tr('wholesale'),
                        context.tr('available'),
                      ),
                    if (product.variants.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        context.tr('variants'),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._groupVariants(product.variants).entries.map((group) {
                        final groupName = group.key;
                        final options = group.value;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                groupName,
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: cs.onSurface.withValues(alpha: 0.6),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: options.map((v) {
                                  final selected = _selectedVariantId == v.id;
                                  return ChoiceChip(
                                    label: Text(v.value),
                                    selected: selected,
                                    selectedColor: cs.primaryContainer,
                                    onSelected: (sel) {
                                      setState(() {
                                        _selectedVariantId = sel ? v.id : null;
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 8),
                      if (_selectedVariantId != null) ...[
                        _buildDetailRow(
                          context.tr('selected'),
                          product.variants
                              .firstWhere((v) => v.id == _selectedVariantId)
                              .value,
                        ),
                        _buildDetailRow(
                          context.tr('price_adjustment'),
                          context.formatPrice(
                            _getSelectedVariant()?.priceAdjustment
                                    ?.toDouble() ??
                                0,
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: cs.primary.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.storefront_outlined,
                            size: 20,
                            color: cs.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: context.tr('posted_on'),
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: cs.onSurface.withValues(
                                        alpha: 0.7,
                                      ),
                                    ),
                                  ),
                                  TextSpan(
                                    text: 'Soko Vibe',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: cs.primary,
                                    ),
                                  ),
                                  TextSpan(
                                    text: context.tr('posted_by'),
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: cs.onSurface.withValues(
                                        alpha: 0.7,
                                      ),
                                    ),
                                  ),
                                  TextSpan(
                                    text: product.sellerName,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                  if (product.sellerKycApproved)
                                    WidgetSpan(child: VerifiedBadge(size: 13)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    GlassCard(
                      onTap: () {
                        if (currentUser == null) {
                          context.push(AppRoutes.login);
                        } else if (sellerId.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Hitilafu: muuzaji hajulikani.')),
                          );
                        } else {
                          context.push(
                            '${AppRoutes.publicProfile}/$sellerId',
                            extra: product.sellerName,
                          );
                        }
                      },
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: cs.primaryContainer,
                            backgroundImage:
                                _sellerProfile?.profileImage.isNotEmpty == true
                                    ? NetworkImage(_sellerProfile!.profileImage)
                                    : null,
                            child: _sellerProfile?.profileImage.isNotEmpty == true
                                ? null
                                : Icon(Icons.person, color: cs.surface),
                          ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                product.sellerName,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15,
                                                  color: cs.onSurface,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (product.sellerKycApproved)
                                              VerifiedBadge(size: 14),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        if (currentUser == null)
                                          Row(
                                            children: [
                                              TextButton(
                                                onPressed: () => context.push(
                                                  AppRoutes.login,
                                                ),
                                                child: Text(
                                                  context.tr('view_store'),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              ElevatedButton.icon(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      cs.whatsappGreen,
                                                ),
                                                icon: Icon(
                                                  Icons.chat,
                                                  color: cs.surface,
                                                  size: 18,
                                                ),
                                                onPressed: _chatWithSeller,
                                                label: Text(
                                                  'Chat',
                                                  style: TextStyle(
                                                    color: cs.onPrimary,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          )
                                        else if (currentUser.uid != sellerId)
                                          Row(
                                            children: [
                                              TextButton(
                                                onPressed: () {
                                                  if (sellerId.isEmpty) {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      const SnackBar(content: Text('Hitilafu: muuzaji hajulikani.')),
                                                    );
                                                  } else {
                                                    context.push(
                                                      '${AppRoutes.publicProfile}/$sellerId',
                                                      extra: product.sellerName,
                                                    );
                                                  }
                                                },
                                                child: Text(
                                                  context.tr('view_store'),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              ElevatedButton.icon(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      cs.whatsappGreen,
                                                ),
                                                icon: Icon(
                                                  Icons.chat,
                                                  color: cs.surface,
                                                  size: 18,
                                                ),
                                                onPressed: _chatWithSeller,
                                                label: Text(
                                                  context.tr('chat'),
                                                  style: TextStyle(
                                                    color: cs.onPrimary,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ReviewSection(productId: product.id),
                    ),
                    const Divider(height: 32),
                    CommentSection(productId: product.id),
                    const Divider(height: 8),
                    const AdBanner(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.whatsappGreen,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: Icon(Icons.chat, color: cs.surface, size: 18),
                onPressed: _chatWithSeller,
                label: Text(
                  context.tr('chat'),
                  style: TextStyle(color: cs.surface, fontSize: 13),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.successGreen,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: Icon(
                  Icons.shopping_cart_checkout,
                  color: cs.surface,
                  size: 18,
                ),
                onPressed: _processing
                    ? null
                    : () async {
                        if (currentUser == null) {
                          context.push(AppRoutes.login);
                        } else if (currentUser.uid == sellerId) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(context.tr('cannot_buy_own')),
                            ),
                          );
                        } else {
                          await _processBuyNow();
                        }
                      },
                label: Text(
                  context.tr('buy_now'),
                  style: TextStyle(color: cs.surface, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, List<ProductVariant>> _groupVariants(
    List<ProductVariant> variants,
  ) {
    final map = <String, List<ProductVariant>>{};
    for (var v in variants) {
      map.putIfAbsent(v.name, () => []).add(v);
    }
    return map;
  }

  double _getEffectivePrice() {
    final variant = _getSelectedVariant();
    return widget.product.price + (variant?.priceAdjustment ?? 0);
  }

  String _getCategoryDisplay(String categoryName) {
    final cached = CategoryService().cached;
    final cat = cached.cast<Category?>().firstWhere(
      (c) => c?.name == categoryName,
      orElse: () => null,
    );
    if (cat != null) return '${cat.nameSw} | ${cat.name}';
    return categoryName;
  }

  ProductVariant? _getSelectedVariant() {
    if (_selectedVariantId == null) return null;
    final variants = widget.product.variants.where(
      (v) => v.id == _selectedVariantId,
    );
    return variants.isNotEmpty ? variants.first : null;
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            "$label: ",
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  void _showFullScreenImage(
    BuildContext context,
    List<String> images,
    int initialIndex,
  ) {
    final cs = Theme.of(context).colorScheme;
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: cs.onSurface,
        pageBuilder: (context, animation, secondaryAnimation) {
          return _FullScreenImageViewer(
            images: images,
            initialIndex: initialIndex,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  Future<void> _processBuyNow() async {
    if (!mounted) return;
    context.push(AppRoutes.checkout, extra: widget.product);
  }

  void _chatWithSeller() {
    ChatNavigation.openSellerChat(context, widget.product.sellerId, widget.product.sellerName);
  }

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${h}h ${m}m ${s}s';
  }

  String _fmtDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _FullScreenImageViewer extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const _FullScreenImageViewer({
    required this.images,
    required this.initialIndex,
  });

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.onSurface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: cs.surface),
        title: Text(
          '${_currentIndex + 1}/${widget.images.length}',
          style: TextStyle(color: cs.surface),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.images.length,
            onPageChanged: (index) {
              setState(() => _currentIndex = index);
            },
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 5.0,
                  child: Center(
                    child: CachedNetworkImage(
                      imageUrl: widget.images[index],
                      fit: BoxFit.contain,
                      placeholder: (context, url) => const Center(
                        child: GoogleLoading(size: 32, strokeWidth: 2),
                      ),
                      errorWidget: (context, error, stackTrace) => Center(
                        child: Icon(
                          Icons.broken_image,
                          color: cs.surface,
                          size: 80,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          if (widget.images.length > 1)
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  widget.images.length,
                  (index) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _currentIndex == index ? 12 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _currentIndex == index
                          ? cs.surface
                          : cs.surface.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
