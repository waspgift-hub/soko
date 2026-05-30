import 'package:flutter/material.dart';
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
    with WidgetsBindingObserver {
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
    final locale = AppConfig.of(context).langCode;
    final started = await _voice.startRecording();
    if (!started) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(locale == 'en' ? 'Sorry, no microphone permission.' : 'Samahani, hakuna ruhusa ya kutumia maikrofoni.')),
        );
      }
      return;
    }

    setState(() => _isRecording = true);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(locale == 'en' ? 'Recording... Tap mic again to stop.' : 'Kurekodi... Bonyeza tena maikrofoni kusimamisha.'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _stopRecording() async {
    final locale = AppConfig.of(context).langCode;
    setState(() => _isRecording = false);
    _messages.add(ChatMessage(text: locale == 'en' ? '[Recording stopped... waiting]' : '[Kurekodi kumesimama... nakusubiri]', isUser: true, isAudio: true));
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
          text: locale == 'en'
              ? 'Sorry boss, I could not hear clearly. Please try again or type the product name.'
              : 'Samahani mkuu, siwezi kusikia vizuri. Tafadhali jaribu tena au andika jina la bidhaa.',
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
        final locale = AppConfig.of(context).langCode;
        _messages.add(ChatMessage(
          text: locale == 'en' ? 'Sorry boss, something went wrong. Please try again.' : 'Samahani mkuu, kuna tatizo. Tafadhali jaribu tena.',
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
    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.smart_toy_outlined, color: Color(0xFF2D6A4F), size: 22),
                SizedBox(width: 8),
                Text('AI Dalali', style: TextStyle(color: Color(0xFF2D6A4F), fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  'mtandaoni',
                  style: TextStyle(color: Colors.green[700], fontSize: 11, fontWeight: FontWeight.w500),
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
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5))],
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
                      style: const TextStyle(color: Colors.black),
                      decoration: InputDecoration(
                        hintText: 'Andika chochote... tafuta, ongea, omba ushauri',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: const Color(0xFF2D6A4F),
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
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
          color: _isRecording ? Colors.red[400] : Colors.grey[200],
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _isRecording
               ? const Icon(Icons.mic_rounded, color: Colors.white, size: 20, key: ValueKey('recording'))
              : const Icon(Icons.mic_none_rounded, color: Color(0xFF2D6A4F), size: 20, key: ValueKey('idle')),
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
        gradient: const LinearGradient(colors: [Color(0xFFFF6F00), Color(0xFFFFA726)]),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.lightbulb_outline, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Mkuu! Dalali ana ushauri',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  'Bidhaa zako ${lowPerf.take(3).map((p) => p.name).join(', ')} hazijapata wateja. Jaribu kupunguza bei au kuboresha maelezo!',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _showSellerTip = false),
            style: TextButton.styleFrom(foregroundColor: Colors.white, padding: const EdgeInsets.all(4)),
            child: const Text('Sawa', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
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
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2D6A4F).withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF2D6A4F),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_rounded, color: Colors.white, size: 14),
                SizedBox(width: 4),
                Text(
                  'IPO KWENYE SOKO LANGU',
                  style: TextStyle(
                    color: Colors.white,
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
                      Text(product.brand!, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFF2D6A4F), borderRadius: BorderRadius.circular(12)),
                child: Text(context.formatPrice(product.price), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ],
          ),
          if (product.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(product.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey[700], fontSize: 13)),
          ],
          const SizedBox(height: 8),
          if (product.category.isNotEmpty) _infoRow(Icons.category, product.category),
          _infoRow(Icons.person, product.sellerName),
          if (product.sellerPhone.isNotEmpty) _infoRow(Icons.phone, product.sellerPhone),
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
              label: const Text('Wasiliana na Muuzaji'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
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
          Icon(icon, size: 16, color: Colors.grey[600]),
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
              decoration: BoxDecoration(color: const Color(0xFF2D6A4F), borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.image_outlined, color: Colors.white, size: 32),
            )
          : msg.isAudio
              ? Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFF2D6A4F), borderRadius: BorderRadius.circular(16)),
                  child: const Icon(Icons.audio_file_rounded, color: Colors.white, size: 32),
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
        color: isUser ? const Color(0xFF2D6A4F) : Colors.grey[100],
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: isUser ? const Radius.circular(20) : const Radius.circular(4),
          bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(20),
        ),
      ),
      child: Text(text, style: TextStyle(color: isUser ? Colors.white : Colors.black87, fontSize: 14)),
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
              'AI anaandika...',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.grey[100],
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
              decoration: const BoxDecoration(
                color: Color(0xFF2D6A4F),
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
