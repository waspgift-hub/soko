import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../extensions/context_tr.dart';
import '../../services/product_service.dart';
import '../../services/user_service.dart';
import '../../services/flash_sale_service.dart';
import '../../models/product_model.dart';
import '../../models/flash_sale_model.dart';
import '../../widgets/product_card.dart';
import '../../widgets/ad_banner.dart';
import '../../app/routes.dart';
import '../../widgets/google_loading.dart';
import '../../utils/responsive.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ProductService _productService = ProductService();
  final UserService _userService = UserService();
  final FlashSaleService _flashSaleService = FlashSaleService();
  bool _loading = false;
  bool _hasSearched = false;
  bool _error = false;
  List<Product>? _lastResults;
  List<UserProfile>? _userResults;
  Map<String, FlashSale> _flashSales = {};
  StreamSubscription? _flashSub;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _flashSub = _flashSaleService.getActiveFlashSalesMap().listen((map) {
      if (mounted) setState(() => _flashSales = map);
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _flashSub?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_searchController.text.isEmpty) {
      setState(() {
        _hasSearched = false;
        _loading = false;
        _error = false;
      });
    }
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _loading = true;
      _error = false;
      _hasSearched = true;
    });

    try {
      final results = await Future.wait([
        _productService.searchProducts(query).first,
        _userService.searchUsers(query),
      ]);
      if (mounted) {
        setState(() {
          _lastResults = results[0] as List<Product>;
          _userResults = results[1] as List<UserProfile>;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = true;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: _searchController,
            autofocus: true,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            decoration: InputDecoration(
              hintText: context.tr('search_products'),
              hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54)),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _hasSearched = false;
                          _loading = false;
                          _error = false;
                          _lastResults = null;
                          _userResults = null;
                        });
                      },
                    )
                  : null,
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _performSearch(),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.search, color: Theme.of(context).colorScheme.primary),
            onPressed: _performSearch,
          ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) return _buildLoadingState();
    if (_error) return _buildErrorState();
    if (!_hasSearched) return _buildInitialState();

    final products = _lastResults ?? [];
    final users = _userResults ?? [];
    if (products.isEmpty && users.isEmpty) return _buildEmptyState();

    return _buildResults(users, products);
  }

  Widget _buildLoadingState() {
    return SingleChildScrollView(
      physics: AlwaysScrollableScrollPhysics(),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            const GoogleLoading(size: 32, strokeWidth: 3),
            const SizedBox(height: 16),
            Text(
              context.tr('searching_soko'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('loading_results'),
              style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInitialState() {
    return SingleChildScrollView(
      physics: AlwaysScrollableScrollPhysics(),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 72, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              context.tr('search_products'),
              style: TextStyle(
                fontSize: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('find_products_people'),
              style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      physics: AlwaysScrollableScrollPhysics(),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off, size: 72, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 16),
              Text(
                context.tr('no_results_soko'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('try_different'),
                style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return SingleChildScrollView(
      physics: AlwaysScrollableScrollPhysics(),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 72, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              context.tr('trouble_connecting'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('try_again'),
              style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _performSearch,
              icon: const Icon(Icons.refresh),
              label: Text(context.tr('try_again')),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(List<UserProfile> users, List<Product> products) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (users.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${context.tr('users')} (${users.length})',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          ...users.map(_buildUserTile),
          const Divider(height: 32),
        ],
        if (products.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${context.tr('products')} (${products.length})',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: Responsive.gridColumns(context),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: Responsive.cardAspectRatio(context),
            ),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              return ProductCard(
                product: product,
                flashSale: _flashSales[product.id],
                onTap: () => context.push(
                  '${AppRoutes.productDetail}/${product.id}',
                  extra: product,
                ),
              );
            },
          ),
        ],
        const SizedBox(height: 16),
        const AdBanner(),
      ],
    );
  }

  Widget _buildUserTile(UserProfile user) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: Theme.of(context).colorScheme.primary,
          backgroundImage: user.profileImage.isNotEmpty
              ? NetworkImage(user.profileImage)
              : null,
          child: user.profileImage.isEmpty
              ? Text(
                  user.displayName.isNotEmpty
                      ? user.displayName[0].toUpperCase()
                      : '?',
                  style: TextStyle(fontSize: 20, color: Theme.of(context).colorScheme.surface, fontWeight: FontWeight.bold),
                )
              : null,
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                user.displayName.isNotEmpty
                    ? user.displayName
                    : context.tr('unknown'),
                style: const TextStyle(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        subtitle: Text(
          user.location.isNotEmpty
              ? user.location
              : user.bio.isNotEmpty
              ? user.bio
              : '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios,
          size: 14,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        onTap: () => context.push(
          '${AppRoutes.publicProfile}/${user.uid}',
          extra: user.displayName,
        ),
      ),
    );
  }
}
