import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../utils/phone_utils.dart';
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
import '../../utils/chat_utils.dart';
import '../../widgets/staggered_fade_in.dart';

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
          .limit(3)
          .get();
      final docs = snap.docs.toList()
        ..sort((a, b) {
          final ta = (a.data()['createdAt'] as Timestamp?) ?? Timestamp.now();
          final tb = (b.data()['createdAt'] as Timestamp?) ?? Timestamp.now();
          return tb.compareTo(ta);
        });
      return docs.map((d) => d.data()).toList();
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
        buffer.writeln('${context.tr('buyer_reviews')} (in-app):');
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
      final products = await _searcher.searchProducts(text);

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

      setState(() {
        _isLoading = false;
        _messages.add(ChatMessage(
          text: reply,
          isUser: false,
          products: products.isNotEmpty ? products : null,
        ));
      });
      _scrollToBottom();
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
      setState(() {
        _isLoading = false;
        _messages.add(ChatMessage(
          text: reply,
          isUser: false,
        ));
      });
      _scrollToBottom();
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
    setState(() {
      _isLoading = false;
      _messages.add(ChatMessage(
        text: reply,
        isUser: false,
        products: products,
      ));
    });
    _scrollToBottom();
  }

  void _chatWithSeller(ProductSearchResult product) {
    final sellerId = product.sellerId.isNotEmpty
        ? product.sellerId
        : FirebaseAuth.instance.currentUser?.uid ?? '';
    if (sellerId.isEmpty) return;
    showChatOptions(
      context: context,
      sellerId: sellerId,
      sellerName: product.sellerName,
      productName: product.productName,
      productPrice: product.price,
      phone: product.sellerPhone.isNotEmpty ? product.sellerPhone : null,
    );
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
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.smart_toy_outlined, color: cs.primary, size: 22),
                const SizedBox(width: 8),
                Text('AI Dalali', style: GoogleFonts.spaceGrotesk(color: cs.onSurface, fontWeight: FontWeight.w600, fontSize: 18)),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                Text(
                  context.tr('online'),
                  style: GoogleFonts.jetBrainsMono(color: cs.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.w500, letterSpacing: 0.3),
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              itemCount: _messages.length + (_isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                if (_isLoading && index == _messages.length) {
                  return const _TypingIndicator();
                }
                final msg = _messages[index];
                if (msg.products != null && msg.products!.isNotEmpty) {
                  return StaggeredFadeIn(
                    index: index,
                    child: _buildProductResults(msg),
                  );
                }
                return StaggeredFadeIn(
                  index: index,
                  child: _buildMessageBubble(msg),
                );
              },
            ),
          ),
          _buildInputBar(cs),
        ],
      ),
    );
  }

  Widget _buildInputBar(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.onSurface.withValues(alpha: 0.05))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _buildMicButton(cs),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _controller,
                textInputAction: TextInputAction.send,
                onSubmitted: _sendMessage,
                style: TextStyle(color: cs.onSurface, fontSize: 14),
                decoration: InputDecoration(
                  hintText: context.tr('ai_chat_hint'),
                  hintStyle: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.4), fontSize: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: cs.onSurface.withValues(alpha: 0.05)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: cs.onSurface.withValues(alpha: 0.05)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: cs.primary.withValues(alpha: 0.3)),
                  ),
                  filled: true,
                  fillColor: cs.onSurface.withValues(alpha: 0.04),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: cs.primary,
                shape: BoxShape.circle,
                border: Border.all(color: cs.onSurface.withValues(alpha: 0.1)),
              ),
              child: IconButton(
                icon: Icon(Icons.send_rounded, color: cs.onPrimary, size: 18),
                onPressed: () => _sendMessage(_controller.text),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMicButton(ColorScheme cs) {
    return GestureDetector(
      onTap: _toggleRecording,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        width: 44, height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _isRecording ? cs.error : cs.onSurface.withValues(alpha: 0.06),
          border: Border.all(
            color: _isRecording ? cs.error : cs.onSurface.withValues(alpha: 0.05),
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _isRecording
            ? Icon(Icons.mic_rounded, color: cs.onError, size: 20, key: const ValueKey('recording'))
            : Icon(Icons.mic_none_rounded, color: cs.onSurface.withValues(alpha: 0.6), size: 20, key: const ValueKey('idle')),
        ),
      ),
    );
  }

  Widget _buildSellerTip() {
    final lowPerf = _sellerProducts.where((p) => p.soldCount == 0 && p.viewCount < 20).toList();
    if (lowPerf.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [cs.primary, cs.primary.withValues(alpha: 0.7)]),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.lightbulb_outline, color: cs.onPrimary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('ai_tip_title'),
                  style: GoogleFonts.spaceGrotesk(color: cs.onPrimary, fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  context.tr('ai_seller_tip').replaceAll('{0}', lowPerf.take(3).map((p) => p.name).join(', ')),
                  style: TextStyle(color: cs.onPrimary.withValues(alpha: 0.9), fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _showSellerTip = false),
            style: TextButton.styleFrom(foregroundColor: cs.onPrimary, padding: const EdgeInsets.all(4)),
            child: Text(context.tr('ok'), style: GoogleFonts.jetBrainsMono(fontWeight: FontWeight.w600, fontSize: 11, color: cs.onPrimary)),
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
            child: _buildAiBubble(msg.text),
          ),
        ...msg.products!.map((p) => _buildProductCard(p)),
      ],
    );
  }

  Widget _buildProductCard(ProductSearchResult product) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_rounded, color: cs.primary, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      context.tr('in_soko_langu'),
                      style: GoogleFonts.jetBrainsMono(
                        color: cs.primary, fontSize: 10,
                        fontWeight: FontWeight.w600, letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
                    Text(product.productName, style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600, fontSize: 15, color: cs.onSurface)),
                    if (product.brand != null && product.brand!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(product.brand!, style: GoogleFonts.jetBrainsMono(color: cs.onSurfaceVariant.withValues(alpha: 0.6), fontSize: 10, letterSpacing: 0.2)),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (product.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(product.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.7), fontSize: 13)),
          ],
          const SizedBox(height: 8),
          if (product.category.isNotEmpty) _infoRow(Icons.category_outlined, product.category, cs),
          _infoRow(Icons.person_outline, product.sellerName, cs),
          if (product.sellerPhone.isNotEmpty) _infoRow(Icons.phone_outlined, PhoneUtils.formatForDisplay(product.sellerPhone), cs),
          _infoRow(Icons.location_on_outlined, product.location, cs),
          if (product.rating > 0) _infoRow(Icons.star_outline, '${product.rating.toStringAsFixed(1)} (${product.reviewCount})', cs),
          if (product.condition != 'new') _infoRow(Icons.info_outline, '${context.tr('condition')}: ${product.condition}', cs),
          if (product.stock > 0) _infoRow(Icons.inventory_2_outlined, 'Stock: ${product.stock}', cs),
          if (product.soldCount > 0) _infoRow(Icons.trending_up, 'Imeuzwa: ${product.soldCount}', cs),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _chatWithSeller(product),
              icon: const Icon(Icons.chat_outlined, size: 16),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(context.tr('contact_seller'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: cs.onSurface.withValues(alpha: 0.08)),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: cs.onSurface.withValues(alpha: 0.4)),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12))),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    return Align(
      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: msg.isImage
          ? _buildMediaBubble(Icons.image_outlined)
          : msg.isAudio
              ? _buildMediaBubble(Icons.audio_file_rounded)
              : StaggeredFadeIn(
                  index: 0,
                  child: msg.isUser
                      ? _buildUserBubble(msg.text)
                      : _buildAiBubble(msg.text),
                ),
    );
  }

  Widget _buildMediaBubble(IconData icon) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.05)),
      ),
      child: Icon(icon, color: cs.onSurface.withValues(alpha: 0.5), size: 28),
    );
  }

  Widget _buildUserBubble(String text) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.15),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(4),
        ),
        border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
      ),
      child: Text(text, style: TextStyle(color: cs.onSurface, fontSize: 14, height: 1.4)),
    );
  }

  Widget _buildAiBubble(String text) {
    final cs = Theme.of(context).colorScheme;
    final glassBorder = cs.onSurface.withValues(alpha: 0.05);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.04),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
          bottomLeft: Radius.circular(4),
          bottomRight: Radius.circular(20),
        ),
        border: Border.all(color: glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome, size: 12, color: cs.primary),
              const SizedBox(width: 4),
              Text('AI', style: GoogleFonts.jetBrainsMono(color: cs.primary, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 8),
          _buildFormattedText(text, cs),
        ],
      ),
    );
  }

  Widget _buildFormattedText(String text, ColorScheme cs) {
    final lines = text.split('\n');
    final children = <InlineSpan>[];
    final boldRegex = RegExp(r'\*\*(.+?)\*\*');
    final headerRegex = RegExp(r'^#{1,3}\s+(.+)', multiLine: false);

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      if (line.trim().isEmpty) {
        if (children.isNotEmpty) {
          children.add(const TextSpan(text: '\n'));
        }
        continue;
      }

      if (headerRegex.hasMatch(line)) {
        final headerText = headerRegex.firstMatch(line)!.group(1)!;
        children.add(TextSpan(
          text: '$headerText\n',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
            height: 1.5,
          ),
        ));
        continue;
      }

      if (line.trimLeft().startsWith('- ') || line.trimLeft().startsWith('* ')) {
        final bulletText = line.trimLeft().substring(2);
        children.add(TextSpan(
          text: '  ${String.fromCharCode(0x2022)}  ',
          style: TextStyle(color: cs.primary, fontSize: 14, height: 1.6),
        ));
        _addBoldText(bulletText, boldRegex, children, cs, isListItem: true);
        children.add(const TextSpan(text: '\n'));
        continue;
      }

      _addBoldText(line, boldRegex, children, cs);
      if (i < lines.length - 1) {
        children.add(const TextSpan(text: '\n'));
      }
    }

    return RichText(
      text: TextSpan(
        style: TextStyle(color: cs.onSurface, fontSize: 14, height: 1.5),
        children: children,
      ),
    );
  }

  void _addBoldText(String text, RegExp boldRegex, List<InlineSpan> spans, ColorScheme cs, {bool isListItem = false}) {
    final matches = boldRegex.allMatches(text).toList();
    if (matches.isEmpty) {
      spans.add(TextSpan(text: text));
      return;
    }

    int lastEnd = 0;
    for (final m in matches) {
      if (m.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, m.start)));
      }
      spans.add(TextSpan(
        text: m.group(1),
        style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface),
      ));
      lastEnd = m.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }
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
    final cs = Theme.of(context).colorScheme;
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
              style: GoogleFonts.jetBrainsMono(
                color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                fontSize: 10,
                letterSpacing: 0.3,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: cs.onSurface.withValues(alpha: 0.04),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(20),
              ),
              border: Border.all(color: cs.onSurface.withValues(alpha: 0.05)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) => _dot(i, cs)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(int index, ColorScheme cs) {
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
              width: 7, height: 7,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.6),
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
