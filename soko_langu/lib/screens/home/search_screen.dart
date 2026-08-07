import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../extensions/context_tr.dart';
import '../../services/search_service.dart';
import '../../services/search_history_service.dart';
import '../../app/routes.dart';
import '../../models/product_model.dart';
import '../../models/category_model.dart';
import '../../widgets/google_loading.dart';
import '../../widgets/soko_vibe_loading.dart';
import '../../widgets/barcode_scanner_widget.dart';
import '../../widgets/soko_vibe_watermark.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final SearchService _searchService = SearchService();
  final SearchHistoryService _historyService = SearchHistoryService();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;

  late TabController _tabCtrl;
  final List<String> _tabs = ['all', 'products', 'sellers', 'categories'];

  List<SearchSuggestion> _suggestions = [];
  List<String> _searchHistory = [];
  List<Map<String, dynamic>> _trending = [];
  SearchResponse? _response;
  bool _loading = false;
  bool _hasSearched = false;
  String _selectedTab = 'all';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) {
        final tab = _tabs[_tabCtrl.index];
        if (tab == _selectedTab) return;
        setState(() => _selectedTab = tab);
        if (_hasSearched && _response != null && _searchCtrl.text.isNotEmpty) {
          _performSearch();
        }
      }
    });
    _searchCtrl.addListener(_onSearchChanged);
    _focusNode.addListener(_onFocusChanged);
    _loadHistory();
    _loadTrending();
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _tabCtrl.dispose();
    _debounce?.cancel();
    _speech.stop();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final h = await _historyService.getHistory();
    if (mounted) setState(() => _searchHistory = h);
  }

  Future<void> _loadTrending() async {
    try {
      final t = await _searchService.getTrendingSearches();
      if (mounted) setState(() => _trending = t);
    } catch (_) {}
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus && _searchCtrl.text.isEmpty) _loadHistory();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    final text = _searchCtrl.text.trim();
    if (text.length >= 2) {
      _debounce = Timer(const Duration(milliseconds: 200), () => _fetchSuggestions(text));
    } else {
      setState(() => _suggestions = []);
    }
  }

  Future<void> _fetchSuggestions(String query) async {
    try {
      final s = await _searchService.autocomplete(query);
      if (mounted && _searchCtrl.text.trim() == query) {
        setState(() => _suggestions = s);
      }
    } catch (_) {}
  }

  Future<void> _performSearch({String? query}) async {
    final q = (query ?? _searchCtrl.text).trim();
    if (q.isEmpty) return;

    _focusNode.unfocus();
    setState(() {
      _loading = true;
      _hasSearched = true;
      _suggestions = [];
    });

    _historyService.addQuery(q);
    if (mounted) _loadHistory();

    try {
      final resp = await _searchService.globalSearch(
        query: q,
        type: _selectedTab,
        pageSize: 30,
      );
      if (mounted) {
        setState(() {
          _response = resp;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _navigateToProduct(String productId) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('products').doc(productId).get();
      if (doc.exists && mounted) {
        final product = Product.fromFirestore(doc);
        context.push('${AppRoutes.productDetail}/$productId', extra: product);
      }
    } catch (_) {
      if (mounted) {
        context.push('${AppRoutes.productDetail}/$productId');
      }
    }
  }

  void _openCategory(String id, String name, {String? image}) {
    final cat = Category(
      id: id.isNotEmpty ? id : name,
      name: name,
      nameSw: name,
      icon: '📦',
      image: image,
      subcategories: const [],
    );
    context.push(
      '${AppRoutes.categoryProducts}/${Uri.encodeComponent(name)}',
      extra: cat,
    );
  }

  void _onSuggestionTap(SearchSuggestion s) {
    _focusNode.unfocus();
    if (s.type == 'product' && s.id != null && s.id!.isNotEmpty) {
      _navigateToProduct(s.id!);
    } else if ((s.type == 'user' || s.type == 'seller') &&
        s.id != null &&
        s.id!.isNotEmpty) {
      context.push('${AppRoutes.publicProfile}/${s.id}', extra: s.text);
    } else if (s.type == 'category') {
      _openCategory(s.id ?? s.text, s.text, image: s.image);
    } else {
      _searchCtrl.text = s.text;
      _performSearch();
    }
  }

  Future<void> _barcodeSearch(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return;
    _focusNode.unfocus();
    setState(() {
      _loading = true;
      _hasSearched = true;
      _suggestions = [];
    });
    try {
      final snap = await FirebaseFirestore.instance
          .collection('products')
          .where('barcode', isEqualTo: trimmed)
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty && mounted) {
        final product = Product.fromFirestore(snap.docs.first);
        context.push('${AppRoutes.productDetail}/${snap.docs.first.id}', extra: product);
        setState(() => _loading = false);
        return;
      }
    } catch (_) {}
    if (mounted) {
      _performSearch(query: trimmed);
    }
  }

  void _clearField() {
    _searchCtrl.clear();
    setState(() {
      _suggestions = [];
      _response = null;
      _hasSearched = false;
      _loading = false;
    });
  }

  Future<void> _removeHistoryItem(String q) async {
    await _historyService.removeQuery(q);
    _loadHistory();
  }

  Future<void> _clearAllHistory() async {
    await _historyService.clearAll();
    _loadHistory();
  }

  Future<void> _startVoiceSearch() async {
    final available = await _speech.initialize();
    if (!available || !mounted) return;
    setState(() => _isListening = true);
    await _speech.listen(
      onResult: (result) {
        if (result.finalResult && result.recognizedWords.isNotEmpty) {
          _searchCtrl.text = result.recognizedWords;
          _performSearch();
        }
      },
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 3),
    );
    if (mounted) setState(() => _isListening = false);
  }

  void _stopVoiceSearch() {
    _speech.stop();
    setState(() => _isListening = false);
  }

  Future<void> _openBarcodeScanner() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerWidget()),
    );
    if (result != null && result.isNotEmpty && mounted) {
      _searchCtrl.text = result;
      _barcodeSearch(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: _buildSearchField(cs),
        bottom: _hasSearched
            ? TabBar(
                controller: _tabCtrl,
                isScrollable: true,
                labelColor: cs.primary,
                unselectedLabelColor: cs.onSurfaceVariant,
                indicatorColor: cs.primary,
                tabs: _tabs.map((t) => Tab(text: context.tr(t))).toList(),
              )
            : _isListening
                ? PreferredSize(
                    preferredSize: const Size.fromHeight(32),
                    child: Container(
                      color: cs.error.withValues(alpha: 0.1),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SokoVibeThreeDotLoader(
                            size: 14, dotSize: 3.5, color: cs.error,
                          ),
                          const SizedBox(width: 8),
                          Text(context.tr('listening'), style: TextStyle(color: cs.error, fontSize: 13)),
                        ],
                      ),
                    ),
                  )
                : null,
      ),
      body: _buildBody(cs),
    );
  }

  Widget _buildSearchField(ColorScheme cs) {
    return SizedBox(
      height: 44,
      child: TextField(
        controller: _searchCtrl,
        focusNode: _focusNode,
        textInputAction: TextInputAction.search,
        style: TextStyle(fontSize: 15, color: cs.onSurface),
        decoration: InputDecoration(
          hintText: context.tr('search_products_users'),
          hintStyle: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
          prefixIcon: Icon(Icons.search, size: 20, color: cs.onSurfaceVariant),
          suffixIcon: _searchCtrl.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, size: 18, color: cs.onSurfaceVariant),
                  onPressed: _clearField,
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: _isListening
                          ? Icon(Icons.mic, size: 20, color: cs.error)
                          : Icon(Icons.mic_none, size: 20, color: cs.onSurfaceVariant),
                      onPressed: _isListening ? _stopVoiceSearch : _startVoiceSearch,
                    ),
                    IconButton(
                      icon: Icon(Icons.qr_code_scanner, size: 20, color: cs.onSurfaceVariant),
                      onPressed: _openBarcodeScanner,
                    ),
                  ],
                ),
          filled: true,
          fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.7)),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        onSubmitted: (q) => _performSearch(query: q),
      ),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_loading) {
      return const Center(child: GoogleLoadingPage());
    }

    if (_suggestions.isNotEmpty && !_hasSearched) {
      return _buildSuggestions(cs);
    }

    if (_response != null) {
      return _buildResults(cs);
    }

    if (_focusNode.hasFocus && _searchCtrl.text.isEmpty) {
      return _buildHistoryPanel(cs);
    }

    return _buildInitialState(cs);
  }

  Widget _buildSuggestions(ColorScheme cs) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: _suggestions.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
      itemBuilder: (_, i) {
        final s = _suggestions[i];
        final IconData typeIcon;
        final Color typeColor;
        if (s.type == 'product') {
          typeIcon = Icons.shopping_bag_outlined;
          typeColor = cs.primary;
        } else if (s.type == 'seller' || s.type == 'user') {
          typeIcon = Icons.storefront_outlined;
          typeColor = cs.secondary;
        } else if (s.type == 'category') {
          typeIcon = Icons.category_outlined;
          typeColor = cs.tertiary;
        } else {
          typeIcon = Icons.search;
          typeColor = cs.onSurfaceVariant;
        }
        return ListTile(
          leading: s.image != null && s.image!.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: s.image!,
                    width: 36, height: 36, fit: BoxFit.cover,
                  ),
                )
              : Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(typeIcon, size: 18, color: typeColor),
                ),
          title: Text(s.text, style: const TextStyle(fontSize: 14)),
          subtitle: Row(
            children: [
              Icon(typeIcon, size: 11, color: typeColor),
              const SizedBox(width: 3),
              Text(
                context.tr(s.type),
                style: TextStyle(fontSize: 11, color: typeColor),
              ),
              if (s.price != null) ...[
                const SizedBox(width: 6),
                Text('· ${context.currencySymbol()} ${s.price!.toStringAsFixed(0)}',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ],
            ],
          ),
          trailing: Icon(Icons.north_west, size: 16, color: cs.onSurfaceVariant),
          dense: true,
          onTap: () => _onSuggestionTap(s),
        );
      },
    );
  }

  Widget _buildResults(ColorScheme cs) {
    final resp = _response!;
    final results = resp.results;

    if (results.isEmpty) {
      return _buildEmptyState(cs, resp);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: results.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 4),
            child: Text(
              '${resp.total} ${context.tr('results').toLowerCase()}',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          );
        }
        final r = results[i - 1];
        return _buildResultCard(cs, r);
      },
    );
  }

  Widget _buildResultCard(ColorScheme cs, SearchResult r) {
    final isProduct = r.type == 'product';
    final isSeller = r.type == 'user' || r.type == 'seller';
    final isCategory = r.type == 'category';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          _searchService.recordClick(
            resultId: r.id,
            resultType: r.type,
            query: _response?.query,
          );
          if (isProduct) {
            _navigateToProduct(r.id);
          } else if (isSeller) {
            context.push('${AppRoutes.publicProfile}/${r.id}', extra: r.displayName);
          } else if (isCategory) {
            _openCategory(r.id, r.displayName, image: r.image);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              if (r.image != null && r.image!.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: r.image!,
                          fit: BoxFit.cover,
                        ),
                        Positioned(
                          bottom: 2,
                          left: 2,
                          child: IgnorePointer(
                            child: SokoVibeWatermark(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(r.displayName,
                              style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14,
                                color: cs.onSurface,
                              ),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        if (r.kycApproved)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Icon(Icons.verified, size: 14, color: Colors.blue),
                          ),
                        if (r.isBoosted)
                          Container(
                            margin: const EdgeInsets.only(left: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(context.tr('ad_label'), style: TextStyle(fontSize: 10, color: cs.primary)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (r.description != null && r.description!.isNotEmpty)
                      Text(r.description!,
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (isProduct && r.price != null)
                      Text('${context.currencySymbol()} ${r.price!.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15,
                            color: cs.primary,
                          )),
                    if (r.sellerName != null || r.location != null)
                      Text(
                        [r.sellerName, r.location].where((x) => x != null && x.isNotEmpty).join(' · '),
                        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                    if (r.rating != null && r.rating! > 0)
                      Row(
                        children: [
                          Icon(Icons.star, size: 14, color: Colors.amber),
                          const SizedBox(width: 2),
                          Text(r.rating!.toStringAsFixed(1),
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                          if (r.reviewCount != null) ...[
                            const SizedBox(width: 4),
                            Text('(${r.reviewCount})',
                                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                          ],
                        ],
                      ),
                    if (isCategory)
                      Row(
                        children: [
                          Icon(Icons.category_outlined, size: 13, color: cs.tertiary),
                          const SizedBox(width: 4),
                          Text(context.tr('categories'),
                              style: TextStyle(fontSize: 11, color: cs.tertiary)),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme cs, SearchResponse resp) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 64, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(context.tr('no_results'), style: TextStyle(fontSize: 18, color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text(
              context.tr('try_different'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
            ),
            if (resp.correction != null) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () {
                  _searchCtrl.text = resp.correction!;
                  _performSearch();
                },
                icon: const Icon(Icons.search, size: 18),
                label: Text('${context.tr('search_for')} "${resp.correction}"'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryPanel(ColorScheme cs) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (_trending.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(Icons.trending_up, size: 18, color: cs.primary),
                const SizedBox(width: 6),
                Text(context.tr('trending'),
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: cs.onSurface)),
              ],
            ),
          ),
          Wrap(
            spacing: 8, runSpacing: 6,
            children: _trending.take(10).map((t) {
              final text = t['text'] as String? ?? '';
              return ActionChip(
                label: Text(text, style: const TextStyle(fontSize: 13)),
                onPressed: () {
                  _searchCtrl.text = text;
                  _performSearch();
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],
        if (_searchHistory.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.history, size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(context.tr('recent_searches'),
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: cs.onSurface)),
                ],
              ),
              TextButton(
                onPressed: _clearAllHistory,
                child: Text(context.tr('clear_all'), style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
              ),
            ],
          ),
          ..._searchHistory.map((q) => ListTile(
                leading: Icon(Icons.history, size: 18, color: cs.onSurfaceVariant),
                title: Text(q, style: const TextStyle(fontSize: 14)),
                trailing: IconButton(
                  icon: Icon(Icons.close, size: 16, color: cs.onSurfaceVariant),
                  onPressed: () => _removeHistoryItem(q),
                ),
                dense: true,
                onTap: () {
                  _searchCtrl.text = q;
                  _performSearch();
                },
              )),
        ],
        if (_searchHistory.isEmpty && _trending.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(Icons.search, size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),
                  Text(context.tr('search_products_users'),
                      style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildInitialState(ColorScheme cs) {
    if (_trending.isNotEmpty) return _buildHistoryPanel(cs);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search, size: 72, color: cs.onSurfaceVariant.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text(context.tr('search_products_users'),
              style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}
