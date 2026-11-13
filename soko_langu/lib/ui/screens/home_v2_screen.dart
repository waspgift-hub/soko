import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../models/product_model.dart';
import '../../providers/product_feed_provider.dart';
import '../tokens.dart';
import '../widgets/ui_button.dart';

class HomeV2Screen extends StatefulWidget {
  const HomeV2Screen({super.key});

  @override
  State<HomeV2Screen> createState() => _HomeV2ScreenState();
}

class _HomeV2ScreenState extends State<HomeV2Screen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProductFeedProvider>().loadInitial();
    });
  }

  @override
  Widget build(BuildContext context) {
    final feed = context.watch<ProductFeedProvider>();
    final products = feed.products;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Soko Vibe'),
        actions: [
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: () => context.push(AppRoutes.search),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => context.read<ProductFeedProvider>().refresh(),
        child: _buildBody(context, feed, products),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ProductFeedProvider feed,
    List<Product> products,
  ) {
    if (products.isEmpty && feed.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (products.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(UiSpace.lg),
        children: [
          Text(
            feed.error ?? 'Hakuna bidhaa bado.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: UiSpace.md),
          UiPrimaryButton(
            label: 'Jaribu tena',
            onPressed: () => context.read<ProductFeedProvider>().refresh(),
          ),
        ],
      );
    }
    return ListView.separated(
      itemCount: products.length + 1,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index == products.length) {
          return _LoadMore(
            hasMore: feed.hasMore,
            busy: feed.isLoading,
            onPressed: () => context.read<ProductFeedProvider>().loadNextPage(),
          );
        }
        return _ProductRow(product: products[index]);
      },
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final image = product.images.isNotEmpty ? product.images.first : null;
    return InkWell(
      onTap: () => context.push(
        AppRoutes.productDetailV2,
        extra: product,
      ),
      child: Padding(
        padding: const EdgeInsets.all(UiSpace.md),
        child: Row(
          children: [
            SizedBox(
              width: 72,
              height: 72,
              child: image == null
                  ? const ColoredBox(color: UiColors.canvas)
                  : Image.network(
                      image,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const ColoredBox(color: UiColors.canvas),
                    ),
            ),
            const SizedBox(width: UiSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: UiSpace.xs),
                  Text(
                    'TSh ${product.price.round()}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Text(
                    product.location,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadMore extends StatelessWidget {
  const _LoadMore({
    required this.hasMore,
    required this.busy,
    required this.onPressed,
  });

  final bool hasMore;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (!hasMore) return const SizedBox(height: UiSpace.lg);
    return Padding(
      padding: const EdgeInsets.all(UiSpace.md),
      child: UiPrimaryButton(
        label: 'Onyesha zaidi',
        onPressed: onPressed,
        busy: busy,
      ),
    );
  }
}
