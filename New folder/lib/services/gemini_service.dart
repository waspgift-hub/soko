import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product_model.dart';
import '../models/flash_sale_model.dart';
import '../services/flash_sale_service.dart';
import 'dart:math';

const String _groqApiKey = ''; // Provide via --dart-define=GROQ_API_KEY at build time
const String _groqModel = 'llama-3.3-70b-versatile';

class DiscountCalculator {
  static final Random _random = Random();

  static Map<String, dynamic> calculateSmartDiscount({
    required double originalPrice,
    required String category,
    required String condition,
    String? location,
  }) {
    double minDiscount = 5;
    double maxDiscount = 25;
    double recommendedDiscount = 10;
    String reason = '';

    final categoryLower = category.toLowerCase();

    if (categoryLower.contains('electronics') || 
        categoryLower.contains('phone') || 
        categoryLower.contains('computer')) {
      minDiscount = 3;
      maxDiscount = 15;
      recommendedDiscount = 8;
      reason = 'Electronics zina margin ya chini, discount ya juu inaweza kuwa hasara.';
    } else if (categoryLower.contains('clothes') || 
               categoryLower.contains('fashion') || 
               categoryLower.contains('shoes')) {
      minDiscount = 10;
      maxDiscount = 30;
      recommendedDiscount = 20;
      reason = 'Mavazi yana margin ya juu, unaweza kutoa discount ya 20-30%.';
    } else if (categoryLower.contains('food') || 
               categoryLower.contains('kitchen') ||
               categoryLower.contains('home')) {
      minDiscount = 5;
      maxDiscount = 20;
      recommendedDiscount = 12;
      reason = 'Bidhaa za home zina margin ya wastani.';
    } else if (categoryLower.contains('cosmetics') ||
               categoryLower.contains('beauty')) {
      minDiscount = 8;
      maxDiscount = 25;
      recommendedDiscount = 15;
      reason = 'Beauty products zina margin ya kati, discount ya 15% inatosha.';
    } else {
      minDiscount = 7;
      maxDiscount = 20;
      recommendedDiscount = 12;
      reason = 'Bidhaa hii ina margin ya wastani.';
    }

    if (condition == 'used' || condition == 'second_hand') {
      minDiscount += 5;
      maxDiscount += 10;
      recommendedDiscount += 8;
      reason += ' Bidhaa ya secondhand inaweza kuwa na discount ya juu zaidi.';
    }

    if (originalPrice < 10000) {
      minDiscount = min(minDiscount, 10);
      maxDiscount = min(maxDiscount, 20);
      recommendedDiscount = min(recommendedDiscount, 15);
    } else if (originalPrice > 100000) {
      recommendedDiscount += 2;
    }

    recommendedDiscount = recommendedDiscount.clamp(minDiscount, maxDiscount);

    final variation = _random.nextDouble() * 3 - 1.5;
    recommendedDiscount = (recommendedDiscount + variation).clamp(minDiscount, maxDiscount);
    recommendedDiscount = double.parse(recommendedDiscount.toStringAsFixed(1));

    final minPrice = originalPrice * (1 - maxDiscount / 100);
    final maxPrice = originalPrice * (1 - minDiscount / 100);
    final recommendedPrice = originalPrice * (1 - recommendedDiscount / 100);

    return {
      'originalPrice': originalPrice,
      'minDiscount': minDiscount,
      'maxDiscount': maxDiscount,
      'recommendedDiscount': recommendedDiscount,
      'minPrice': minPrice,
      'maxPrice': maxPrice,
      'recommendedPrice': recommendedPrice,
      'reason': reason,
    };
  }

  static bool isDiscountSafe(double discountPercent, double originalPrice) {
    final minSafePrice = originalPrice * 0.5;
    final discountedPrice = originalPrice * (1 - discountPercent / 100);
    return discountedPrice >= minSafePrice;
  }
}

class DiscountRequest {
  final String productId;
  final String productName;
  final double originalPrice;
  final double requestedDiscount;
  final double requestedPrice;
  final String buyerId;
  final String buyerName;
  final String sellerId;
  final DateTime createdAt;
  final String status;

  DiscountRequest({
    required this.productId,
    required this.productName,
    required this.originalPrice,
    required this.requestedDiscount,
    required this.requestedPrice,
    required this.buyerId,
    required this.buyerName,
    required this.sellerId,
    required this.createdAt,
    this.status = 'pending',
  });

  factory DiscountRequest.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return DiscountRequest(
      productId: data['productId'] ?? '',
      productName: data['productName'] ?? '',
      originalPrice: (data['originalPrice'] ?? 0).toDouble(),
      requestedDiscount: (data['requestedDiscount'] ?? 0).toDouble(),
      requestedPrice: (data['requestedPrice'] ?? 0).toDouble(),
      buyerId: data['buyerId'] ?? '',
      buyerName: data['buyerName'] ?? '',
      sellerId: data['sellerId'] ?? '',
      createdAt: data['createdAt'] is Timestamp 
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      status: data['status'] ?? 'pending',
    );
  }

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'productName': productName,
    'originalPrice': originalPrice,
    'requestedDiscount': requestedDiscount,
    'requestedPrice': requestedPrice,
    'buyerId': buyerId,
    'buyerName': buyerName,
    'sellerId': sellerId,
    'createdAt': FieldValue.serverTimestamp(),
    'status': status,
  };
}

class GroqService {
  static final GroqService _instance = GroqService._internal();
  factory GroqService() => _instance;
  GroqService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FlashSaleService _flashSaleService = FlashSaleService();
  final List<Map<String, String>> _chatHistory = [];

  final String _systemPrompt = '''Wewe ni "Soko Vibe AI Assistant" — dalali mahiri wa Soko Vibe (soko la kidijitali la Tanzania).

LUGHA: Kiswahili cha Kitanzania (cha kileo, cha mtaani lakini chenye heshima).
TONE: Professional lakini friendly. Tumia maneno ya biashara: "Karibu sana bosi", "Mchongo wa haraka", "Ofa ya kushtukiza", "Wahi mchongo!".

KAZI YAKO:
1. KUPENDEKESA BIDHAA: Analyze products na kupendekeza kulingana na mahitaji ya user.
2. KUANGALIA BEI: Compare prices, check market rates, calculate fair discounts.
3. NEGOTIATION: Usaidie watumiaji kuomba discount. Wauzaji wanaweza kukubali au kukataa.
4. FLASH SALES: Create smart flash sales based on product margins.

BEI NA DISCOUNT RULES:
- Kila product ina different margin - USIFANYIE discount 30% kwa wote!
- Electronics: 3-15% discount max (margin ya chini)
- Clothes/Fashion: 10-30% discount (margin ya juu)
- Food/Home: 5-20% discount (margin ya wastani)
- Used items: +5-10% discount
- Products chini ya 10K: max 15% discount
- Products zaidi ya 100K: inaweza kutoa 25%+

NEGOTIATION FLOW:
- User anaweza kuomba discount ya % yoyote
- AI icheckee kama discount ni reasonable kwa product hiyo
- AI imwambie user kama inawezekana au iaharibu seller
- Kama discount ni fair, AI inaweza kumpelekea seller

SAMPLE RESPONSES:
"Katika kiatu hiki cha 25,000 TZS, discount ya 10-15% (2,500-3,750 TZS) ni fair kwa sababu margin ya shoes ni ya wastani. Unaweza kuomba 15%."
"Bidhaa hii ya electronics 150,000 TZS, discount ya 5% (7,500 TZS) tu ndio reasonable kwa sababu margin ya electronics ni ya chini sana."
"Discount ya 40% kwa bidhaa ya 5,000 TZS itakuwa hasara kwa muuzaji! Maximum ni 15%."

USIRAHISISHE:
- Usitoa passwords za watumiaji au backend logs.
- Toa tu nambari za simu za biashara za umma.
- Ikiwa swali halihusiani na Soko Vibe, jibu kwa ufupi na uelekeze kwenye biashara ya app.''';

  Future<String> sendMessage(
    String message, {
    List<Product>? availableProducts,
    List<FlashSale>? activeFlashSales,
    Product? targetProduct,
  }) async {
    try {
      String contextInfo = '';

      if (availableProducts != null && availableProducts.isNotEmpty) {
        contextInfo += '\n\n=== BIDHAA ZINAZOPATIKANA ===\n';
        for (var p in availableProducts.take(15)) {
          final discountCalc = DiscountCalculator.calculateSmartDiscount(
            originalPrice: p.price,
            category: p.category,
            condition: p.condition,
          );
          contextInfo += '- ${p.name}\n  Bei: TSh ${p.price.toStringAsFixed(0)}\n  Fair Discount: ${discountCalc['minDiscount']}-${discountCalc['maxDiscount']}%\n  Muuzaji: ${p.sellerName} | ${p.location}\n\n';
        }
      }

      if (targetProduct != null) {
        final calc = DiscountCalculator.calculateSmartDiscount(
          originalPrice: targetProduct.price,
          category: targetProduct.category,
          condition: targetProduct.condition,
          location: targetProduct.location,
        );
        contextInfo += '\n\n=== PRODUCT YAKO ILIYOANGALIWA ===\n';
        contextInfo += 'Jina: ${targetProduct.name}\n';
        contextInfo += 'Bei ya sasa: TSh ${targetProduct.price.toStringAsFixed(0)}\n';
        contextInfo += 'Category: ${targetProduct.category}\n';
        contextInfo += 'Condition: ${targetProduct.condition}\n';
        contextInfo += 'Fair Discount Range: ${calc['minDiscount']}-${calc['maxDiscount']}%\n';
        contextInfo += 'Recommended Price: TSh ${calc['recommendedPrice'].toStringAsFixed(0)}\n';
        contextInfo += 'Reason: ${calc['reason']}\n';
      }

      if (activeFlashSales != null && activeFlashSales.isNotEmpty) {
        contextInfo += '\n\n=== FLASH SALES ZINAZOENDELA ===\n';
        for (var s in activeFlashSales) {
          contextInfo += '- ${s.productName}: ${s.discountPercent}% off (TSh ${s.flashPrice.toStringAsFixed(0)})\n';
        }
      }

      final fullMessage = '$message\n\n$contextInfo';

      _chatHistory.add({'role': 'user', 'content': fullMessage});

      final response = await http.post(
        Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer $_groqApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': _groqModel,
          'messages': [
            {'role': 'system', 'content': _systemPrompt},
            ..._chatHistory,
          ],
          'temperature': 0.7,
          'max_tokens': 1024,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final assistantMessage = data['choices'][0]['message']['content'] as String;
        _chatHistory.add({'role': 'assistant', 'content': assistantMessage});
        return assistantMessage;
      } else {
        return 'Samahani, kuna tatizo la teknolojia. Jaribu tena baada ya dakika chache.';
      }
    } catch (e) {
      return 'Hitilafu: $e';
    }
  }

  Map<String, dynamic> analyzeProductForDiscount(Product product) {
    return DiscountCalculator.calculateSmartDiscount(
      originalPrice: product.price,
      category: product.category,
      condition: product.condition,
      location: product.location,
    );
  }

  Future<bool> submitDiscountRequest({
    required Product product,
    required double requestedDiscount,
    required String buyerId,
    required String buyerName,
  }) async {
    try {
      final calc = analyzeProductForDiscount(product);
      final maxFairDiscount = calc['maxDiscount'] as double;
      final requestedPrice = product.price * (1 - requestedDiscount / 100);

      if (requestedDiscount > maxFairDiscount + 5) {
        return false;
      }

      final request = DiscountRequest(
        productId: product.id,
        productName: product.name,
        originalPrice: product.price,
        requestedDiscount: requestedDiscount,
        requestedPrice: requestedPrice,
        buyerId: buyerId,
        buyerName: buyerName,
        sellerId: product.sellerId,
        createdAt: DateTime.now(),
      );

      await _db.collection('discount_requests').add(request.toMap());

      await _db.collection('notifications').add({
        'userId': product.sellerId,
        'title': '💰 Ombi la Discount!',
        'body': '$buyerName anahitaji discount ya $requestedDiscount% kwa ${product.name}. Bei yaombwa: TSh ${requestedPrice.toStringAsFixed(0)}',
        'type': 'discount_request',
        'productId': product.id,
        'productName': product.name,
        'requestedDiscount': requestedDiscount,
        'requestedPrice': requestedPrice,
        'createdAt': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<List<Product>> searchProducts(String query, {String? category, String? location}) async {
    Query queryRef = _db.collection('products').where('isActive', isEqualTo: true);

    if (category != null && category.isNotEmpty) {
      queryRef = queryRef.where('category', isEqualTo: category);
    }

    if (location != null && location.isNotEmpty) {
      queryRef = queryRef.where('location', isEqualTo: location);
    }

    final snapshot = await queryRef.get();
    final products = snapshot.docs.map((doc) => Product.fromFirestore(doc)).toList();

    if (query.isNotEmpty) {
      return products.where((p) =>
        p.name.toLowerCase().contains(query.toLowerCase()) ||
        p.description.toLowerCase().contains(query.toLowerCase()) ||
        p.category.toLowerCase().contains(query.toLowerCase())
      ).toList();
    }

    return products;
  }

  Future<List<FlashSale>> getActiveFlashSales() async {
    final snapshot = await _db
        .collection('flash_sales')
        .where('isActive', isEqualTo: true)
        .where('status', isEqualTo: 'active')
        .get();

    return snapshot.docs
        .map((doc) => FlashSale.fromFirestore(doc))
        .where((sale) => sale.isLive)
        .toList();
  }

  Future<FlashSale?> createFlashSale({
    required String productId,
    required String productName,
    required String productImage,
    required String sellerId,
    required String sellerName,
    required String sellerPhone,
    required String location,
    required String category,
    required double originalPrice,
    required double flashPrice,
    required int durationHours,
    required int maxQuantity,
    required String aiReason,
  }) async {
    return _flashSaleService.createFlashSale(
      productId: productId,
      productName: productName,
      productImage: productImage,
      sellerId: sellerId,
      sellerName: sellerName,
      sellerPhone: sellerPhone,
      location: location,
      category: category,
      originalPrice: originalPrice,
      flashPrice: flashPrice,
      durationHours: durationHours,
      maxQuantity: maxQuantity,
      aiReason: aiReason,
    );
  }

  void resetChat() {
    _chatHistory.clear();
  }
}

class GeminiService {
  static final GeminiService _instance = GeminiService._internal();
  factory GeminiService() => _instance;
  GeminiService._internal();

  final GroqService _groqService = GroqService();

  void init() {}

  Future<String> sendMessage(
    String message, {
    List<Product>? availableProducts,
    List<FlashSale>? activeFlashSales,
    Product? targetProduct,
  }) {
    return _groqService.sendMessage(
      message,
      availableProducts: availableProducts,
      activeFlashSales: activeFlashSales,
      targetProduct: targetProduct,
    );
  }

  Map<String, dynamic> analyzeProductForDiscount(Product product) {
    return _groqService.analyzeProductForDiscount(product);
  }

  Future<bool> submitDiscountRequest({
    required Product product,
    required double requestedDiscount,
    required String buyerId,
    required String buyerName,
  }) {
    return _groqService.submitDiscountRequest(
      product: product,
      requestedDiscount: requestedDiscount,
      buyerId: buyerId,
      buyerName: buyerName,
    );
  }

  Future<List<Product>> searchProducts(String query, {String? category, String? location}) {
    return _groqService.searchProducts(query, category: category, location: location);
  }

  Future<List<FlashSale>> getActiveFlashSales() {
    return _groqService.getActiveFlashSales();
  }

  Future<FlashSale?> createFlashSale({
    required String productId,
    required String productName,
    required String productImage,
    required String sellerId,
    required String sellerName,
    required String sellerPhone,
    required String location,
    required String category,
    required double originalPrice,
    required double flashPrice,
    required int durationHours,
    required int maxQuantity,
    required String aiReason,
  }) {
    return _groqService.createFlashSale(
      productId: productId,
      productName: productName,
      productImage: productImage,
      sellerId: sellerId,
      sellerName: sellerName,
      sellerPhone: sellerPhone,
      location: location,
      category: category,
      originalPrice: originalPrice,
      flashPrice: flashPrice,
      durationHours: durationHours,
      maxQuantity: maxQuantity,
      aiReason: aiReason,
    );
  }

  void resetChat() {
    _groqService.resetChat();
  }
}