import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../extensions/context_tr.dart';
import '../../services/product_service.dart';
import '../../services/user_service.dart';
import '../../models/product_model.dart';
import '../../widgets/product_card.dart';
import '../../widgets/ad_banner.dart';
import '../../widgets/verified_badge.dart';
import '../../app/routes.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ProductService _productService = ProductService();
  final UserService _userService = UserService();
  bool _loading = false;
  bool _hasSearched = false;
  bool _error = false;
  List<Product>? _lastResults;
  List<UserProfile>? _userResults;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
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
        title: TextField(
          controller: _searchController,
          autofocus: true,
          style: const TextStyle(color: Colors.black),
          decoration: InputDecoration(
            hintText: context.tr('search_products'),
            border: InputBorder.none,
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
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.green),
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
            const Icon(Icons.search, size: 48, color: Colors.green),
            const SizedBox(height: 16),
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.green[400],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.tr('searching_soko'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('loading_results'),
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
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
            Icon(Icons.search, size: 72, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              context.tr('search_products'),
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Find products and people across Tanzania',
              style: TextStyle(fontSize: 14, color: Colors.grey[400]),
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
              Icon(Icons.search_off, size: 72, color: Colors.grey[300]),
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
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
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
            Icon(Icons.cloud_off, size: 72, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              context.tr('trouble_connecting'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('try_again'),
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _performSearch,
              icon: const Icon(Icons.refresh),
              label: Text(context.tr('try_again')),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
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
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.7,
            ),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              return ProductCard(
                product: product,
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
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: Colors.green,
          backgroundImage: user.profileImage.isNotEmpty
              ? NetworkImage(user.profileImage)
              : null,
          child: user.profileImage.isEmpty
              ? Text(
                  user.displayName.isNotEmpty
                      ? user.displayName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    fontSize: 20,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
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
            VerifiedBadge(tier: user.accountTier, size: 14),
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
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios,
          size: 14,
          color: Colors.grey,
        ),
        onTap: () => context.push(
          '${AppRoutes.publicProfile}/${user.uid}',
          extra: user.displayName,
        ),
      ),
    );
  }
}
