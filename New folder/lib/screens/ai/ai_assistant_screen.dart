import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/gemini_service.dart';
import '../../models/product_model.dart';
import '../../models/flash_sale_model.dart';

class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  final GeminiService _gemini = GeminiService();
  final TextEditingController _controller = TextEditingController();
  final List<_ChatMessage> _messages = [];
  bool _loading = false;
  List<Product> _products = [];
  List<FlashSale> _flashSales = [];

  @override
  void initState() {
    super.initState();
    _gemini.init();
    _loadData();
    _messages.add(
      _ChatMessage(
        text:
            'Karibu sana bosi! 🛍️ Mimi ni SOKO LANGU AI — dalali wako wa Soko Langu. Ninaweza:\n\n🔥 Kuwaongoza kwenye Flash Sales\n📦 Kupendekeza bidhaa kulingana na mahitaji yako\n💰 Kuunda Flash Sale kwa bidhaa zako zilizokaa\n📍 Kupata wauzaji karibu nawe\n\nNi nini unachohitaji leo?',
        isUser: false,
        type: 'text',
      ),
    );
  }

  Future<void> _loadData() async {
    _products = await _gemini.searchProducts('');
    _flashSales = await _gemini.getActiveFlashSales();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _loading) return;

    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: true, type: 'text'));
      _loading = true;
      _controller.clear();
    });

    final response = await _gemini.sendMessage(
      text,
      availableProducts: _products,
      activeFlashSales: _flashSales,
    );

    if (mounted) {
      setState(() {
        _messages.add(_ChatMessage(text: response, isUser: false, type: 'text'));
        _loading = false;
      });
    }
  }

  void _onQuickAction(String action) {
    _controller.text = action;
    _sendMessage();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.smart_toy, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            const Text('Soko Langu AI Assistant'),
          ],
        ),
        actions: [
          if (_flashSales.isNotEmpty)
            Badge(
              label: Text('${_flashSales.length}'),
              child: IconButton(
                icon: const Icon(Icons.local_fire_department),
                tooltip: 'Flash Sales',
                onPressed: () => _showFlashSalesSheet(),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Anza mazungumzo mapya',
            onPressed: () {
              _gemini.resetChat();
              setState(() {
                _messages.clear();
                _messages.add(
                  _ChatMessage(
                    text: 'Mazungumzo mapya! 🔄 Karibu bosi, ninaweza kukusaidia vipi leo?',
                    isUser: false,
                    type: 'text',
                  ),
                );
              });
              _loadData();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_flashSales.isNotEmpty) _buildFlashSaleBanner(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                return _buildMessageBubble(msg);
              },
            ),
          ),
          if (_loading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text('AI inachambua...', style: TextStyle(color: Colors.grey[600])),
                ],
              ),
            ),
          _buildQuickActions(),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildFlashSaleBanner() {
    final sale = _flashSales.first;
    return GestureDetector(
      onTap: () => _showFlashSalesSheet(),
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.red[700]!, Colors.orange[600]!],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.local_fire_department, color: Colors.white, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '🔥 ${sale.productName}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'TSh ${sale.flashPrice.toStringAsFixed(0)} | ${sale.discountPercent.toStringAsFixed(0)}% OFF',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Text(
                    'Saa ${sale.timeRemaining.inHours} zilibaki!',
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white),
          ],
        ),
      ),
    );
  }

  void _showFlashSalesSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.local_fire_department, color: Colors.red[700]),
                  const SizedBox(width: 8),
                  Text('🔥 Flash Sales Zinazoendelea', style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _flashSales.length,
                itemBuilder: (context, index) {
                  final sale = _flashSales[index];
                  return _buildFlashSaleCard(sale);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlashSaleCard(FlashSale sale) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          if (sale.productImage.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: CachedNetworkImage(
                imageUrl: sale.productImage,
                height: 120,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sale.productName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      'TSh ${sale.originalPrice.toStringAsFixed(0)}',
                      style: const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.grey),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'TSh ${sale.flashPrice.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.red),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red[100],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '-${sale.discountPercent.toStringAsFixed(0)}%',
                        style: TextStyle(color: Colors.red[700], fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.location_on, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(sale.location, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    const Spacer(),
                    Icon(Icons.access_time, size: 14, color: Colors.orange[700]),
                    const SizedBox(width: 4),
                    Text(
                      '${sale.timeRemaining.inHours}h zilibaki',
                      style: TextStyle(fontSize: 12, color: Colors.orange[700], fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.store, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(sale.sellerName, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    if (sale.sellerPhone.isNotEmpty) ...[
                      const Spacer(),
                      InkWell(
                        onTap: () {},
                        child: Row(
                          children: [
                            Icon(Icons.phone, size: 14, color: Colors.green[700]),
                            const SizedBox(width: 4),
                            Text(sale.sellerPhone, style: TextStyle(fontSize: 12, color: Colors.green[700])),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value: sale.soldQuantity / sale.maxQuantity,
                        backgroundColor: Colors.grey[300],
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.red[700]!),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${sale.maxQuantity - sale.soldQuantity}/${sale.maxQuantity} zilibaki',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _quickActionBtn('🔥 Flash Sales', Icons.local_fire_department, () => _onQuickAction('Nionyeshie flash sales')),
            const SizedBox(width: 8),
            _quickActionBtn('📦 Bidhaa', Icons.shopping_bag, () => _onQuickAction('Nipendekeze bidhaa')),
            const SizedBox(width: 8),
            _quickActionBtn('💰 Kuza Bidhaa', Icons.sell, () => _onQuickAction('Nisaidie kuza bidhaa yangu')),
            const SizedBox(width: 8),
            _quickActionBtn('📍 Karibu Naumi', Icons.location_on, () => _onQuickAction('Wauzaji karibu nami')),
            const SizedBox(width: 8),
            _quickActionBtn('💬 Omba Discount', Icons.discount, () => _showDiscountDialog()),
          ],
        ),
      ),
    );
  }

  void _showDiscountDialog() {
    double selectedDiscount = 10;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.discount, color: Color(0xFF2D6A4F)),
              SizedBox(width: 8),
              Text('Omba Discount'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Chagua discount unayoomba:',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              Slider(
                value: selectedDiscount,
                min: 5,
                max: 40,
                divisions: 7,
                label: '${selectedDiscount.toInt()}%',
                activeColor: const Color(0xFF2D6A4F),
                onChanged: (v) => setDialogState(() => selectedDiscount = v),
              ),
              Center(
                child: Text(
                  '${selectedDiscount.toInt()}% Discount',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2D6A4F),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Discount yako itapelekwa kwa muuzaji kwa idhini yao.',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _controller.text = 'Nataka discount ya ${selectedDiscount.toInt()}% kwa bidhaa yangu';
                _sendMessage();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2D6A4F),
              ),
              child: const Text('Omba', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickActionBtn(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(_ChatMessage msg) {
    final isUser = msg.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: isUser ? const Radius.circular(4) : null,
            bottomLeft: !isUser ? const Radius.circular(4) : null,
          ),
        ),
        child: Text(
          msg.text,
          style: TextStyle(
            color: isUser
                ? Theme.of(context).colorScheme.onPrimary
                : Theme.of(context).colorScheme.onSurface,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(context).padding.bottom + 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: 'Uliza AI dalali wako...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              onSubmitted: (_) => _sendMessage(),
              maxLines: null,
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white, size: 20),
              onPressed: _loading ? null : _sendMessage,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatMessage {
  final String text;
  final bool isUser;
  final String type;
  _ChatMessage({required this.text, required this.isUser, this.type = 'text'});
}
