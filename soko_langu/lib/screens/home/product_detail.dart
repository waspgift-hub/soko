import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/product_model.dart';
import '../../models/cart_model.dart';
import '../../services/cart_service.dart';
import '../../services/wishlist_service.dart';
import '../../services/ad_revenue_service.dart';
import '../../extensions/context_tr.dart';
import '../chat/chat_page.dart';
import '../profile/public_profile_screen.dart';
import '../payment/payment_summary_screen.dart';
import '../../widgets/ad_banner.dart';
import '../../widgets/review_section.dart';
import '../../widgets/verified_badge.dart';
import '../../main.dart';

class ProductDetailPage extends StatefulWidget {
  final Product product;

  const ProductDetailPage({super.key, required this.product});

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  final WishlistService _wishlistService = WishlistService();
  final CartService _cartService = CartService();
  int _quantity = 1;
  bool _isFav = false;
  String? _selectedVariantId;

  @override
  void initState() {
    super.initState();
    _checkFav();
  }

  Future<void> _checkFav() async {
    final fav = await _wishlistService.isFavorite(widget.product.id);
    if (mounted) setState(() => _isFav = fav);
  }

  Future<void> _toggleFav() async {
    await _wishlistService.toggle(widget.product.id);
    setState(() => _isFav = !_isFav);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isFav ? "Added to wishlist" : "Removed from wishlist"),
        ),
      );
    }
  }

  Future<void> _addToCart() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final variant = _getSelectedVariant();
    final adjustedPrice =
        widget.product.price + (variant?.priceAdjustment ?? 0);
    final item = CartItem(
      productId: widget.product.id,
      name:
          widget.product.name + (variant != null ? " (${variant.value})" : ""),
      price: adjustedPrice,
      image: widget.product.images.isNotEmpty
          ? widget.product.images.first
          : null,
      quantity: _quantity,
      sellerId: widget.product.sellerId,
      selectedVariant: variant != null
          ? {
              'id': variant.id,
              'name': variant.name,
              'value': variant.value,
              'priceAdjustment': variant.priceAdjustment,
              'stock': variant.stock,
            }
          : null,
    );
    try {
      await _cartService.addToCart(item);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.tr('added_to_cart'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  Future<void> _buyNow() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid == widget.product.sellerId) return;
    final total = _getEffectivePrice() * _quantity;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentSummaryScreen(
          sellerId: widget.product.sellerId,
          sellerName: widget.product.sellerName,
          productId: widget.product.id,
          productName: widget.product.name,
          productPrice: total,
          paymentMethod: 'Direct Transfer',
        ),
      ),
    );
  }

  Widget _paymentOption(BuildContext ctx, String method) {
    return Card(
      color: Colors.green[50],
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(Icons.radio_button_checked, color: Colors.green),
        title: Row(
          children: [
            Icon(Icons.payment, size: 20, color: Colors.grey[700]),
            const SizedBox(width: 8),
            Text(method, style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  void _shareProduct(Product product) {
    final text =
        "${product.name}\n"
        "Price: ${product.currency ?? 'TSh'} ${product.price.toStringAsFixed(0)}\n"
        "Check it out on Soko Langu!";
    Share.share(text);
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final product = widget.product;
    final sellerId = product.sellerId;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(context.tr('product_detail')),
        actions: [
          IconButton(
            icon: const Icon(Icons.share, color: Colors.green),
            onPressed: () => _shareProduct(product),
          ),
          IconButton(
            icon: Icon(
              _isFav ? Icons.favorite : Icons.favorite_border,
              color: _isFav ? Colors.red : null,
            ),
            onPressed: _toggleFav,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 300,
              child: product.images.isNotEmpty
                  ? PageView.builder(
                      itemCount: product.images.length,
                      itemBuilder: (context, index) {
                        return Image.network(
                          product.images[index],
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                                color: Colors.grey[200],
                                child: const Icon(Icons.image, size: 50),
                              ),
                        );
                      },
                    )
                  : Container(
                      color: Colors.grey[200],
                      child: const Icon(Icons.image, size: 50),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "${product.currency ?? 'TSh'} ${product.price.toStringAsFixed(0)}",
                    style: const TextStyle(
                      color: Colors.blue,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_selectedVariantId != null)
                    Text(
                      "With variant: ${product.currency ?? 'TSh'} ${_getEffectivePrice().toStringAsFixed(0)}",
                      style: const TextStyle(color: Colors.green, fontSize: 14),
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
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "${product.soldCount} ${context.tr('sold')}",
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    context.tr('description'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    product.description,
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    context.tr('details'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildDetailRow(context.tr('category'), product.category),
                  if (product.brand != null)
                    _buildDetailRow(context.tr('brand'), product.brand!),
                  _buildDetailRow(context.tr('condition'), product.condition),
                  _buildDetailRow(context.tr('location'), product.location),
                  _buildDetailRow(
                    context.tr('stock'),
                    "${product.stock} units",
                  ),
                  if (product.isWholesale)
                    _buildDetailRow(context.tr('wholesale'), "Available"),
                  if (product.variants.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      "Variants",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
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
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.6),
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
                                  selectedColor: Colors.green[100],
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
                        "Selected",
                        product.variants
                            .firstWhere((v) => v.id == _selectedVariantId)
                            .value,
                      ),
                      _buildDetailRow(
                        "Price Adjustment",
                        "${product.currency ?? 'TSh'} ${_getSelectedVariant()?.priceAdjustment?.toStringAsFixed(0) ?? '0'}",
                      ),
                    ],
                  ],
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        StreamBuilder<bool>(
                          stream: presenceService.isOnline(sellerId),
                          builder: (context, snap) {
                            final online = snap.data ?? false;
                            return Stack(
                              children: [
                                const CircleAvatar(
                                  backgroundColor: Colors.blueAccent,
                                  child: Icon(
                                    Icons.person,
                                    color: Colors.white,
                                  ),
                                ),
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: online
                                          ? Colors.green
                                          : Colors.grey,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.tr('seller'),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.6),
                                ),
                              ),
                              Text(
                                product.sellerName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              VerifiedBadge(tier: product.sellerTier),
                            ],
                          ),
                        ),
                        if (currentUser != null &&
                            currentUser.uid != sellerId) ...[
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatPage(
                                    receiverId: sellerId,
                                    receiverName: product.sellerName,
                                    productName: product.name,
                                  ),
                                ),
                              );
                            },
                            child: Text(
                              context.tr('chat'),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PublicProfileScreen(
                                    userId: sellerId,
                                    userName: product.sellerName,
                                  ),
                                ),
                              );
                            },
                            child: Text(context.tr('view_store')),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Text(
                        "${context.tr('quantity')}: ",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        onPressed: _quantity > 1
                            ? () => setState(() => _quantity--)
                            : null,
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text("$_quantity", style: const TextStyle(fontSize: 18)),
                      IconButton(
                        onPressed: _quantity < product.stock
                            ? () => setState(() => _quantity++)
                            : null,
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                      const Spacer(),
                      Text(
                        "${context.tr('total')}: ${product.currency ?? 'TSh'} ${(_getEffectivePrice() * _quantity).toStringAsFixed(0)}",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ReviewSection(productId: product.id),
            ),
            const SizedBox(height: 8),
            _AdViewTracker(
              sellerId: widget.product.sellerId,
              productId: widget.product.id,
            ),
            const AdBanner(),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _addToCart,
                child: Text(context.tr('add_to_cart')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _buyNow,
                child: Text(
                  context.tr('buy_now'),
                  style: const TextStyle(color: Colors.white),
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

  ProductVariant? _getSelectedVariant() {
    if (_selectedVariantId == null) return null;
    try {
      return widget.product.variants.firstWhere(
        (v) => v.id == _selectedVariantId,
      );
    } catch (_) {
      return null;
    }
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

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final myTier = userDoc.data()?['accountTier'] as String? ?? 'free';
    if (myTier != 'free') return;

    final sellerDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.sellerId)
        .get();
    final sellerTier = sellerDoc.data()?['accountTier'] as String? ?? 'free';
    if (sellerTier == 'free') return;

    await AdRevenueService().recordAdView(
      sellerId: widget.sellerId,
      sellerTier: sellerTier,
      productId: widget.productId,
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
