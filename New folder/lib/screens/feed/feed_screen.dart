import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../models/product_model.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';
import '../../widgets/google_loading.dart';
import 'package:cached_network_image/cached_network_image.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  int _refreshKey = 0;
  NativeAd? _nativeAd;
  bool _nativeAdLoaded = false;

  static const int adInterval = 8;

  @override
  void initState() {
    super.initState();
    _loadNativeAd();
  }

  void _loadNativeAd() {
    _nativeAd = NativeAd(
      adUnitId: 'ca-app-pub-3940256099942544/2247696110',
      factoryId: 'feed_native',
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (_) => setState(() => _nativeAdLoaded = true),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _nativeAdLoaded = false;
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _nativeAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          context.tr('discover'),
          style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface),
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          key: ValueKey('feed_$_refreshKey'),
          stream: FirebaseFirestore.instance
              .collection('products')
              .orderBy('createdAt', descending: true)
              .limit(50)
              .snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const GoogleLoadingPage();
            }
            final products = snap.data?.docs ?? [];
            if (products.isEmpty) {
              return RefreshIndicator(
                onRefresh: _handleRefresh,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SizedBox(
                    height: MediaQuery.of(context).size.height * 0.6,
                    child: _buildEmpty(context, cs),
                  ),
                ),
              );
            }

            final totalItems = products.length + (products.length ~/ adInterval);

            return RefreshIndicator(
              onRefresh: _handleRefresh,
              child: GridView.builder(
                padding: EdgeInsets.fromLTRB(
                  12,
                  12,
                  12,
                  MediaQuery.of(context).padding.bottom + 12,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.7,
                ),
                itemCount: totalItems,
                itemBuilder: (context, index) {
                  final adIndex = index ~/ (adInterval + 1);
                  final isAdPosition = (index + 1) % (adInterval + 1) == 0;

                  if (isAdPosition && _nativeAdLoaded) {
                    return _buildNativeAdCard(cs);
                  }

                  final productIndex = index - adIndex;
                  if (productIndex >= products.length) {
                    return const SizedBox.shrink();
                  }

                  final data = products[productIndex].data() as Map<String, dynamic>;
                  final product = Product(
                    id: products[productIndex].id,
                    name: data['name'] ?? '',
                    price: (data['price'] as num?)?.toDouble() ?? 0,
                    description: data['description'] ?? '',
                    images: (data['images'] as List?)?.cast<String>() ?? [],
                    category: data['category'] ?? '',
                    subcategory: data['subcategory'] ?? '',
                    location: data['location'] ?? '',
                    sellerId: data['sellerId'] ?? '',
                    sellerName: data['sellerName'] ?? '',
                    createdAt: data['createdAt'] != null
                        ? (data['createdAt'] as Timestamp).toDate()
                        : DateTime.now(),
                    stock: (data['stock'] as num?)?.toInt() ?? 0,
                  );
                  return _buildProductCard(context, product, cs);
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _handleRefresh() async {
    setState(() => _refreshKey++);
  }

  Widget _buildEmpty(BuildContext context, ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.shopping_bag_outlined,
              size: 64,
              color: cs.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            context.tr('no_products'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('no_products_subtitle'),
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(BuildContext context, Product product, ColorScheme cs) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('${AppRoutes.productDetail}/${product.id}', extra: product),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  product.images.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: product.images.first,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => _buildPlaceholder(cs),
                        )
                      : _buildPlaceholder(cs),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: cs.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'TZS ${product.price.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined, size: 12, color: cs.onSurfaceVariant),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          product.location,
                          style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
    );
  }

  Widget _buildNativeAdCard(ColorScheme cs) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.primary.withOpacity(0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.primary.withOpacity(0.08),
              cs.primary.withOpacity(0.03),
            ],
          ),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    color: isDark ? const Color(0xFF1A1A1A) : Colors.grey[100],
                    child: Center(
                      child: Icon(
                        Icons.storefront_outlined,
                        size: 48,
                        color: cs.primary.withOpacity(0.4),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('sponsored'),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: cs.primary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.tr('discover_deals'),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.trending_up, size: 10, color: cs.primary),
                          const SizedBox(width: 2),
                          Text(
                            context.tr('trending_now'),
                            style: TextStyle(fontSize: 9, color: cs.primary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  context.tr('ad'),
                  style: TextStyle(
                    color: cs.primary,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(ColorScheme cs) {
    return Container(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: 40,
          color: cs.onSurfaceVariant.withOpacity(0.4),
        ),
      ),
    );
  }
}

