import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../utils/phone_utils.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/ai/ai_service.dart';
import '../../services/product_search_service.dart';
import '../../main.dart';
import '../../services/product_service.dart';
import '../../services/voice_search_service.dart';
import '../../services/localization_service.dart';
import '../../models/product_model.dart';
import '../../models/product_search_result.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';

class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final AiService _ai = AiService.instance;
  final ProductSearchService _searcher = ProductSearchService();
  final VoiceSearchService _voice = VoiceSearchService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isRecording = false;
  List<Product> _sellerProducts = [];
  bool _showSellerTip = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkSellerProducts();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_messages.isEmpty) {
      _messages.add(ChatMessage(
        text: context.tr('ai_greeting'),
        isUser: false,
      ));
    }
  }

  Future<void> _checkSellerProducts() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final products = await ProductService().getMyProducts().first;
    if (products.isEmpty) return;
    setState(() {
      _sellerProducts = products;
      _showSellerTip = products.any((p) => p.soldCount == 0 && p.viewCount < 20);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _scrollController.dispose();
    _voice.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _isRecording) {
      _stopRecording();
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    final started = await _voice.startRecording();
    if (!started) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('ai_mic_permission_denied'))),
        );
      }
      return;
    }

    setState(() => _isRecording = true);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('ai_recording_hint')),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _stopRecording() async {
    final locale = AppConfig.of(context).langCode;
    setState(() => _isRecording = false);
    _messages.add(ChatMessage(text: context.tr('ai_recording_stopped'), isUser: true, isAudio: true));
    _scrollToBottom();

    final path = await _voice.stopRecording();
    if (path == null || path.isEmpty) return;

    setState(() => _isLoading = true);
    _scrollToBottom();

    final transcribed = await _voice.transcribeAudio(path, locale: locale);
    if (transcribed.isEmpty) {
      setState(() {
        _messages.removeLast();
        _messages.add(ChatMessage(
          text: context.tr('ai_hear_error'),
          isUser: false,
        ));
        _isLoading = false;
      });
      _scrollToBottom();
      return;
    }

    setState(() {
      _messages.removeLast();
      _messages.add(ChatMessage(text: transcribed, isUser: true));
      _isLoading = true;
    });
    _scrollToBottom();

    final products = await _searcher.searchProducts(transcribed);
    await _showProductResults(transcribed, products);
  }

  Future<List<Map<String, dynamic>>> _fetchCommentsForProduct(String productId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('products').doc(productId)
          .collection('comments')
          .orderBy('createdAt', descending: true)
          .limit(3)
          .get();
      return snap.docs.map((d) => d.data()).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchReviewsForProduct(String productId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('reviews')
          .where('productId', isEqualTo: productId)
          .get();
      final docs = snap.docs.toList()
        ..sort((a, b) {
          final ta = (a.data()['createdAt'] as Timestamp?) ?? Timestamp.now();
          final tb = (b.data()['createdAt'] as Timestamp?) ?? Timestamp.now();
          return tb.compareTo(ta);
        });
      return docs.take(3).map((d) => d.data()).toList();
    } catch (_) {
      return [];
    }
  }

  Future<String> _buildRichContext(List<ProductSearchResult> products) async {
    final buffer = StringBuffer();
    final curSym = LocalizationService.supportedCurrencies[
      AppConfig.of(context).currencyCode]?['symbol'] ?? 'TSh';
    for (int i = 0; i < products.length; i++) {
      buffer.writeln(products[i].toContextBlock(i + 1, currencySymbol: curSym));

      final comments = await _fetchCommentsForProduct(products[i].productId);
      if (comments.isNotEmpty) {
        buffer.writeln('Maoni ya wanunuzi (ndani ya app):');
        for (int j = 0; j < comments.length; j++) {
          final c = comments[j];
          buffer.writeln('  ${j + 1}. ${c['userName'] ?? 'Mtu'}: "${c['text'] ?? ''}"');
        }
      }

      final reviews = await _fetchReviewsForProduct(products[i].productId);
      if (reviews.isNotEmpty) {
        buffer.writeln('Ukadiriaji (ndani ya app):');
        for (int j = 0; j < reviews.length; j++) {
          final r = reviews[j];
          final stars = r['rating'] ?? 0;
          buffer.writeln(
            '  ${j + 1}. ${r['userName'] ?? 'Mtu'} — $stars/5: "${r['comment'] ?? ''}"',
          );
        }
      }
      buffer.writeln('');
    }
    return AiService.buildInAppCatalogContext(buffer.toString());
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _isLoading = true;
    });
    _scrollToBottom();
    _controller.clear();

    try {
      // STEP 1: Search products FIRST
      final products = await _searcher.searchProducts(text);

      // STEP 2: Build rich context from real data
      String? richContext;
      if (products.isNotEmpty) {
        richContext = await _buildRichContext(products);
        _ai.addPreference(text);
      }

      final locale = AppConfig.of(context).langCode;
      final reply = await _ai.sendMessage(
        text,
        productContext: richContext,
        catalogStatus: products.isNotEmpty
            ? AiCatalogStatus.foundInApp
            : AiCatalogStatus.notFoundInApp,
        searchQuery: text,
        locale: locale,
      );

      setState(() => _isLoading = false);
      _scrollToBottom();
      await Future.delayed(const Duration(milliseconds: 400));

      setState(() {
        _messages.add(ChatMessage(
          text: reply,
          isUser: false,
          products: products.isNotEmpty ? products : null,
        ));
      });
    } catch (_) {
      setState(() {
        _isLoading = false;
        _messages.add(ChatMessage(
        text: context.tr('ai_generic_error'),
          isUser: false,
        ));
      });
    }

    _scrollToBottom();
  }

  Future<void> _showProductResults(String query, List<ProductSearchResult> products) async {
    final locale = AppConfig.of(context).langCode;
    if (products.isEmpty) {
      final reply = await _ai.sendMessage(
        query,
        productContext: AiService.buildNotFoundCatalogContext(query),
        catalogStatus: AiCatalogStatus.notFoundInApp,
        searchQuery: query,
        locale: locale,
      );
      setState(() => _isLoading = false);
      _scrollToBottom();
      await Future.delayed(const Duration(milliseconds: 400));
      setState(() {
        _messages.add(ChatMessage(
          text: reply,
          isUser: false,
        ));
      });
      return;
    }

    final richContext = await _buildRichContext(products);
    _ai.addPreference(query);

    final reply = await _ai.sendMessage(
      query,
      productContext: richContext,
      catalogStatus: AiCatalogStatus.foundInApp,
      searchQuery: query,
      locale: locale,
    );
    setState(() => _isLoading = false);
    _scrollToBottom();
    await Future.delayed(const Duration(milliseconds: 400));
    setState(() {
      _messages.add(ChatMessage(
        text: reply,
        isUser: false,
        products: products,
      ));
    });
  }

  void _openProductWhatsApp(ProductSearchResult product) {
    final sellerId = product.sellerId.isNotEmpty
        ? product.sellerId
        : FirebaseAuth.instance.currentUser?.uid ?? '';
    if (sellerId.isEmpty) return;
    context.push('${AppRoutes.chat}/$sellerId', extra: {'name': product.sellerName});
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.smart_toy_outlined, color: Theme.of(context).colorScheme.primary, size: 22),
                const SizedBox(width: 8),
                Text('AI Dalali', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  context.tr('online'),
                  style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 11, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ],
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          if (_showSellerTip) _buildSellerTip(),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                if (_isLoading && index == _messages.length) {
                  return const _TypingIndicator();
                }
                final msg = _messages[index];
                if (msg.products != null && msg.products!.isNotEmpty) {
                  return _buildProductResults(msg);
                }
                return _buildMessageBubble(msg);
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5))],
            ),
            child: SafeArea(
              child: Row(
                  children: [
                  _buildMicButton(),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _sendMessage,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                      decoration: InputDecoration(
                        hintText: context.tr('ai_chat_hint'),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: IconButton(
                      icon: Icon(Icons.send_rounded, color: Theme.of(context).colorScheme.surface, size: 20),
                      onPressed: () => _sendMessage(_controller.text),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMicButton() {
    return GestureDetector(
      onTap: _toggleRecording,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _isRecording ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.outlineVariant,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _isRecording
               ? Icon(Icons.mic_rounded, color: Theme.of(context).colorScheme.surface, size: 20, key: ValueKey('recording'))
              : Icon(Icons.mic_none_rounded, color: Theme.of(context).colorScheme.primary, size: 20, key: ValueKey('idle')),
        ),
      ),
    );
  }

  Widget _buildSellerTip() {
    final lowPerf = _sellerProducts.where((p) => p.soldCount == 0 && p.viewCount < 20).toList();
    if (lowPerf.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Theme.of(context).colorScheme.trendingOrange, Theme.of(context).colorScheme.trendingOrange.withValues(alpha: 0.7)]),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.lightbulb_outline, color: Theme.of(context).colorScheme.surface, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('ai_tip_title'),
                  style: TextStyle(color: Theme.of(context).colorScheme.surface, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  context.tr('ai_seller_tip').replaceAll('{0}', lowPerf.take(3).map((p) => p.name).join(', ')),
                  style: TextStyle(color: Theme.of(context).colorScheme.surface, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _showSellerTip = false),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.surface, padding: const EdgeInsets.all(4)),
            child: Text(context.tr('ok'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildProductResults(ChatMessage msg) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (msg.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildBubble(msg.text, false),
          ),
        ...msg.products!.map((p) => _buildProductCard(p)),
      ],
    );
  }

  Widget _buildProductCard(ProductSearchResult product) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_rounded, color: Theme.of(context).colorScheme.surface, size: 14),
                const SizedBox(width: 4),
                Text(
                  context.tr('in_soko_langu'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.surface,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (product.firstImage != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(product.firstImage!, width: 64, height: 64, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                ),
              if (product.firstImage != null) const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.productName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    if (product.brand != null && product.brand!.isNotEmpty)
                      Text(product.brand!, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(12)),
                child: Text(context.formatPrice(product.price), style: TextStyle(color: Theme.of(context).colorScheme.surface, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ],
          ),
          if (product.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(product.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.85), fontSize: 13)),
          ],
          const SizedBox(height: 8),
          if (product.category.isNotEmpty) _infoRow(Icons.category, product.category),
          _infoRow(Icons.person, product.sellerName),
          if (product.sellerPhone.isNotEmpty) _infoRow(Icons.phone, PhoneUtils.formatForDisplay(product.sellerPhone)),
          _infoRow(Icons.location_on, product.location),
          if (product.rating > 0) _infoRow(Icons.star, '${product.rating.toStringAsFixed(1)} (${product.reviewCount})'),
          if (product.condition != 'new') _infoRow(Icons.info_outline, 'Hali: ${product.condition}'),
          if (product.stock > 0) _infoRow(Icons.inventory, 'Stock: ${product.stock}'),
          if (product.soldCount > 0) _infoRow(Icons.trending_up, 'Imeuzwa: ${product.soldCount}'),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _openProductWhatsApp(product),
              icon: const Icon(Icons.chat_outlined, size: 18),
              label: Text(context.tr('contact_seller')),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.whatsappGreen,
                foregroundColor: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    return Align(
      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: msg.isImage
          ? Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(16)),
              child: Icon(Icons.image_outlined, color: Theme.of(context).colorScheme.surface, size: 32),
            )
          : msg.isAudio
              ? Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(16)),
                  child: Icon(Icons.audio_file_rounded, color: Theme.of(context).colorScheme.surface, size: 32),
                )
              : _buildBubble(msg.text, msg.isUser),
    );
  }

  Widget _buildBubble(String text, bool isUser) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
      decoration: BoxDecoration(
        color: isUser ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: isUser ? const Radius.circular(20) : const Radius.circular(4),
          bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(20),
        ),
      ),
      child: Text(text, style: TextStyle(color: isUser ? Theme.of(context).colorScheme.surface : Theme.of(context).colorScheme.onSurface, fontSize: 14)),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(
              context.tr('ai_typing'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(20),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) => _dot(i)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(int index) {
    final delay = index * 200;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = (_controller.value * 1200 - delay).clamp(0, 400) / 400;
        final scale = t > 0 && t <= 1
            ? 0.4 + 0.6 * (t < 0.5 ? 2 * t : 2 * (1 - t))
            : 0.4;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      },
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final bool isImage;
  final bool isAudio;
  final List<ProductSearchResult>? products;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.isImage = false,
    this.isAudio = false,
    this.products,
  });
}


