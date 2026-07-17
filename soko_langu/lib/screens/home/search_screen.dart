import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../extensions/context_tr.dart';
import '../../services/product_service.dart';
import '../../services/user_service.dart';
import '../../services/flash_sale_service.dart';
import '../../services/search_history_service.dart';
import '../../models/product_model.dart';
import '../../models/flash_sale_model.dart';
import '../../widgets/product_card.dart';
import '../../widgets/ad_banner.dart';
import '../../widgets/google_loading.dart';
import '../../app/routes.dart';
import '../../utils/responsive.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ProductService _productService = ProductService();
  final UserService _userService = UserService();
  final FlashSaleService _flashSaleService = FlashSaleService();
  final SearchHistoryService _historyService = SearchHistoryService();
  bool _loading = false;
  bool _hasSearched = false;
  bool _error = false;
  List<Product>? _lastResults;
  List<UserProfile>? _userResults;
  Map<String, FlashSale> _flashSales = {};
  StreamSubscription? _flashSub;
  List<String> _searchHistory = [];

  StreamSubscription<List<Product>>? _liveSearchSub;
  List<Product> _liveResults = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _focusNode.addListener(_onFocusChanged);
    _flashSub = _flashSaleService.getActiveFlashSalesMap().listen((map) {
      if (mounted) setState(() => _flashSales = map);
    });
    _loadHistory();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _flashSub?.cancel();
    _liveSearchSub?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final history = await _historyService.getHistory();
    if (mounted) {
      setState(() {
        _searchHistory = history;
      });
    }
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus && _searchController.text.isEmpty && mounted) {
      _loadHistory();
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    _debounce?.cancel();
    if (query.isEmpty) {
      _liveSearchSub?.cancel();
      _liveSearchSub = null;
      if (mounted) setState(() => _liveResults = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 200), () {
      _startLiveSearch(query);
    });
  }

  void _startLiveSearch(String query) {
    _liveSearchSub?.cancel();
    _liveSearchSub = _productService.searchByNameStream(query).listen(
      (results) {
        if (mounted) setState(() => _liveResults = results);
      },
      onError: (_) {
        if (mounted) setState(() {});
      },
    );
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    _liveSearchSub?.cancel();
    _liveSearchSub = null;

    await _historyService.addQuery(query);
    _searchHistory.remove(query);
    _searchHistory.insert(0, query);
    if (_searchHistory.length > 10) _searchHistory = _searchHistory.sublist(0, 10);

    setState(() {
      _loading = true;
      _error = false;
      _hasSearched = true;
      _liveResults = [];
    });

    try {
      final results = await Future.wait([
        _productService.searchProductsOnce(query),
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

  void _clearField() {
    _searchController.clear();
    _liveSearchSub?.cancel();
    _liveSearchSub = null;
    _liveResults = [];
    _loadHistory();
    setState(() {
      _hasSearched = false;
      _loading = false;
      _error = false;
      _lastResults = null;
      _userResults = null;
    });
  }

  Future<void> _removeHistoryItem(String query) async {
    await _historyService.removeQuery(query);
    if (mounted) {
      setState(() => _searchHistory.remove(query));
    }
  }

  Future<void> _clearAllHistory() async {
    await _historyService.clearAll();
    if (mounted) {
      setState(() => _searchHistory.clear());
    }
  }

  List<String> get _filteredHistory {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _searchHistory;
    return _searchHistory
        .where((h) => h.toLowerCase().contains(q))
        .toList();
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
            focusNode: _focusNode,
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
                      onPressed: _clearField,
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

    final query = _searchController.text.trim();

    // Show live results as user types
    if (query.isNotEmpty && _liveResults.isNotEmpty) {
      return _buildLiveResults();
    }

    // Show "searching" indicator while debounce is pending
    if (query.isNotEmpty && _liveResults.isEmpty && _liveSearchSub != null) {
      return _buildSearchingState();
    }

    // Show full search results
    if (_hasSearched) {
      final products = _lastResults ?? [];
      final users = _userResults ?? [];
      if (products.isEmpty && users.isEmpty) return _buildEmptyState();
      return _buildResults(users, products);
    }

    // Show history or initial state
    if (_focusNode.hasFocus && _searchController.text.isEmpty) {
      return _buildHistoryPanel();
    }

    return _buildInitialState();
  }

  Widget _buildHistoryPanel() {
    final filtered = _filteredHistory;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (filtered.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  context.tr('recent_searches'),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                TextButton.icon(
                  onPressed: _clearAllHistory,
                  icon: const Icon(Icons.delete_sweep, size: 18),
                  label: Text(context.tr('clear_all')),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final query = filtered[index];
                return ListTile(
                  leading: Icon(
                    Icons.history,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                  title: Text(query),
                  onTap: () => _selectQuery(query),
                  trailing: IconButton(
                    icon: Icon(
                      Icons.close,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    onPressed: () => _removeHistoryItem(query),
                  ),
                );
              },
            ),
          ),
        ] else ...[
          Expanded(child: _buildInitialState()),
        ],
      ],
    );
  }

  void _selectQuery(String query) {
    _searchController.text = query;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: query.length),
    );
    _performSearch();
  }

  Widget _buildSearchingState() {
    return const Center(
      child: GoogleLoading(size: 32, strokeWidth: 2.5),
    );
  }

  Widget _buildLiveResults() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            '${context.tr('products')} (${_liveResults.length})',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: Responsive.gridColumns(context),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: Responsive.cardAspectRatio(context),
            ),
            itemCount: _liveResults.length,
            itemBuilder: (context, index) {
              final product = _liveResults[index];
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
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
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
      physics: const AlwaysScrollableScrollPhysics(),
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
      physics: const AlwaysScrollableScrollPhysics(),
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
      physics: const AlwaysScrollableScrollPhysics(),
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
