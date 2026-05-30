import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';
import 'package:go_router/go_router.dart';
import '../../models/product_model.dart';
import '../../models/category_model.dart';
import '../../services/wishlist_service.dart';
import '../../services/ad_revenue_service.dart';
import '../../services/category_service.dart';
import '../../services/localization_service.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../widgets/ad_banner.dart';
import '../../widgets/google_loading.dart';
import '../../widgets/review_section.dart';
import '../../widgets/comment_section.dart';
import '../../services/product_service.dart';
import '../../services/cart_service.dart';
import '../../services/user_service.dart';
import '../../models/cart_model.dart';

class ProductDetailPage extends StatefulWidget {
  final Product product;

  const ProductDetailPage({super.key, required this.product});

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  final WishlistService _wishlistService = WishlistService();
  final CartService _cartService = CartService();
  final UserService _userService = UserService();
  bool _isFav = false;
  String? _selectedVariantId;
  final PageController _imageController = PageController();
  int _currentImageIndex = 0;
  UserProfile? _sellerProfile;

  @override
  void initState() {
    super.initState();
    _checkFav();
    _loadSellerProfile();
  }

  Future<void> _loadSellerProfile() async {
    final profile = await _userService.getProfile(widget.product.sellerId);
    if (mounted) setState(() => _sellerProfile = profile);
  }

  @override
  void dispose() {
    _imageController.dispose();
    super.dispose();
  }

  Future<void> _checkFav() async {
    final fav = await _wishlistService.isFavorite(widget.product.id);
    if (mounted) setState(() => _isFav = fav);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ProductService().incrementViewCount(widget.product.id);
  }

  Future<void> _toggleFav() async {
    await _wishlistService.toggle(widget.product.id);
    setState(() => _isFav = !_isFav);
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
              color: _isFav ? Colors.red : null,
            ),
            onPressed: _toggleFav,
          ),
          if (currentUser != null && currentUser.uid != sellerId)
            IconButton(
              icon: Icon(Icons.flag_outlined, color: Colors.red[300]),
              onPressed: () => context.push(AppRoutes.report, extra: {
                'reportedUserId': sellerId,
                'reportedUserName': product.sellerName,
                'productId': product.id,
                'productName': product.name,
              }),
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
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.3,
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
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(
                                    color: cs.surfaceContainerLow,
                                    child: const Center(
                                      child: GoogleLoading(size: 24, strokeWidth: 2),
                                    ),
                                  ),
                                  errorWidget: (context, error, stackTrace) =>
                                      Container(
                                        color: cs.surfaceContainerHighest,
                                        child: const Icon(Icons.image, size: 50),
                                      ),
                                ),
                              );
                            },
                          )
                        : Container(
                            color: cs.surfaceContainerHighest,
                            child: const Icon(Icons.image, size: 50),
                          ),
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
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.5),
                              border: Border.all(
                                color: Colors.black.withValues(alpha: 0.2),
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
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_currentImageIndex + 1}/${product.images.length}',
                          style: const TextStyle(
                            color: Colors.white,
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
                      const Icon(Icons.photo_library, size: 16, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        'Picha ${product.images.length}',
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
                    Text(
                      context.formatPrice(product.price),
                      style: const TextStyle(
                        color: Colors.blue,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_selectedVariantId != null)
                      Text(
                        "${context.tr('with_variant')} ${context.formatPrice(_getEffectivePrice())}",
                        style: TextStyle(
                          color: cs.primary,
                          fontSize: 14,
                        ),
                      ),
                    if (product.rating > 0) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.star, color: Colors.amber[700], size: 20),
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
                          context.formatPrice(_getSelectedVariant()?.priceAdjustment?.toDouble() ?? 0),
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
                                    text: 'Imepostiwa kwenye ',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: cs.onSurface.withValues(alpha: 0.7),
                                    ),
                                  ),
                                  TextSpan(
                                    text: 'Soko Langu',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: cs.primary,
                                    ),
                                  ),
                                  TextSpan(
                                    text: ' na ',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: cs.onSurface.withValues(alpha: 0.7),
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
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Material(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          if (currentUser == null) {
                            context.push(AppRoutes.login);
                          } else {
                            context.push(
                              '${AppRoutes.publicProfile}/$sellerId',
                              extra: product.sellerName,
                            );
                          }
                        },
                        child: Column(
                          children: [
                            if (_sellerProfile != null &&
                                _sellerProfile!.shopBanner.isNotEmpty)
                              Container(
                                height: 100,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: _sellerProfile!.shopBannerColor.isNotEmpty
                                      ? Color(int.parse(
                                              'FF${_sellerProfile!.shopBannerColor.replaceFirst('#', '')}',
                                              radix: 16))
                                      : cs.primaryContainer,
                                  image: DecorationImage(
                                    image: NetworkImage(
                                        _sellerProfile!.shopBanner),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Stack(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: _sellerProfile?.shopAccentColor.isNotEmpty == true
                                            ? Color(int.parse(
                                                    'FF${_sellerProfile!.shopAccentColor.replaceFirst('#', '')}',
                                                    radix: 16))
                                            : cs.primaryContainer,
                                        backgroundImage: _sellerProfile?.profileImage.isNotEmpty == true
                                            ? NetworkImage(
                                                _sellerProfile!.profileImage)
                                            : null,
                                        child: _sellerProfile?.profileImage.isNotEmpty == true
                                            ? null
                                            : const Icon(
                                                Icons.person,
                                                color: Colors.white,
                                              ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          context.tr('seller'),
                                          style: TextStyle(
                                            color: cs.onSurface
                                                .withValues(alpha: 0.6),
                                          ),
                                        ),
                                        Text(
                                          product.sellerName,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: cs.onSurface,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (currentUser == null) ...[
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFF25D366),
                                      ),
                                      icon: const Icon(Icons.chat,
                                          color: Colors.white, size: 18),
                                      onPressed: () => context.push(
                                          '${AppRoutes.chat}/$sellerId',
                                          extra: {
                                            'name': product.sellerName
                                          }),
                                      label: Text(
                                        context.tr('whatsapp'),
                                        style:
                                            TextStyle(color: cs.onPrimary),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    TextButton(
                                      onPressed: () =>
                                          context.push(AppRoutes.login),
                                      child:
                                          Text(context.tr('view_store')),
                                    ),
                                  ] else if (currentUser.uid != sellerId) ...[
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFF25D366),
                                      ),
                                      icon: const Icon(Icons.chat,
                                          color: Colors.white, size: 18),
                                      onPressed: () => context.push(
                                          '${AppRoutes.chat}/$sellerId',
                                          extra: {
                                            'name': product.sellerName
                                          }),
                                      label: Text(
                                        context.tr('whatsapp'),
                                        style:
                                            TextStyle(color: cs.onPrimary),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    TextButton(
                                      onPressed: () => context.push(
                                        '${AppRoutes.publicProfile}/$sellerId',
                                        extra: product.sellerName,
                                      ),
                                      child: Text(
                                          context.tr('view_store')),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
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
                    _AdViewTracker(
                      sellerId: widget.product.sellerId,
                      productId: widget.product.id,
                    ),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF2D6A4F),
                      side: const BorderSide(color: Color(0xFF2D6A4F)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.add_shopping_cart, size: 18),
                    onPressed: () async {
                      if (currentUser == null) {
                        context.push(AppRoutes.login);
                      } else if (currentUser.uid == sellerId) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(context.tr('cannot_buy_own'))),
                        );
                      } else {
                        try {
                          await _cartService.addToCart(CartItem(
                            productId: widget.product.id,
                            name: widget.product.name,
                            image: widget.product.images.isNotEmpty ? widget.product.images.first : '',
                            price: _getEffectivePrice(),
                            sellerId: sellerId,
                            sellerName: widget.product.sellerName,
                          ));
                          if (mounted) context.push(AppRoutes.cart);
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(context.tr('cart_error').replaceAll('{0}', '$e'))),
                            );
                          }
                        }
                      }
                    },
                    label: Text(context.tr('cart'), style: TextStyle(fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF065535),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.shopping_cart_checkout, color: Colors.white, size: 18),
                    onPressed: () async {
                      if (currentUser == null) {
                        context.push(AppRoutes.login);
                      } else if (currentUser.uid == sellerId) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(context.tr('cannot_buy_own'))),
                        );
                      } else {
                        try {
                          await _cartService.addToCart(CartItem(
                            productId: widget.product.id,
                            name: widget.product.name,
                            image: widget.product.images.isNotEmpty ? widget.product.images.first : '',
                            price: _getEffectivePrice(),
                            sellerId: sellerId,
                            sellerName: widget.product.sellerName,
                          ));
                          if (mounted) context.push(AppRoutes.checkout, extra: [
                            CartItem(
                              productId: widget.product.id,
                              name: widget.product.name,
                              image: widget.product.images.isNotEmpty ? widget.product.images.first : '',
                              price: _getEffectivePrice(),
                              sellerId: sellerId,
                              sellerName: widget.product.sellerName,
                            )
                          ]);
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(context.tr('cart_error').replaceAll('{0}', '$e'))),
                            );
                          }
                        }
                      }
                    },
                    label: Text(context.tr('buy_now'), style: TextStyle(color: Colors.white, fontSize: 15)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.chat, color: Colors.white, size: 18),
                onPressed: () => context.push('${AppRoutes.chat}/$sellerId', extra: {'name': product.sellerName}),
                label: Text(context.tr('whatsapp'), style: TextStyle(color: Colors.white, fontSize: 15)),
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
    final variants =
        widget.product.variants.where((v) => v.id == _selectedVariantId);
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
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          '${_currentIndex + 1}/${widget.images.length}',
          style: const TextStyle(color: Colors.white),
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
                      errorWidget: (context, error, stackTrace) => const Center(
                        child: Icon(Icons.broken_image, color: Colors.white, size: 80),
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
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.4),
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

class _AdViewTracker extends StatefulWidget {
  final String sellerId;
  final String productId;
  const _AdViewTracker({required this.sellerId, required this.productId});

  @override
  State<_AdViewTracker> createState() => _AdViewTrackerState();
}

class _AdViewTrackerState extends State<_AdViewTracker> {
  @override
  void initState() {
    super.initState();
    _track();
  }

  Future<void> _track() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await AdRevenueService().recordAdView(
      sellerId: widget.sellerId,
      productId: widget.productId,
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
