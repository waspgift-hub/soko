import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/flash_sale_model.dart';
import '../models/product_model.dart';
import '../services/notification_service.dart';
import 'gemini_service.dart';

class FlashSaleService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final NotificationService _notif = NotificationService();
  final GeminiService _gemini = GeminiService();

  Stream<List<FlashSale>> getActiveFlashSales() {
    return _db
        .collection('flash_sales')
        .where('isActive', isEqualTo: true)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snapshot) {
      final sales = snapshot.docs
          .map((doc) => FlashSale.fromFirestore(doc))
          .where((sale) => sale.isLive)
          .toList();
      sales.sort((a, b) => a.endTime.compareTo(b.endTime));
      return sales;
    });
  }

  Future<List<Product>> getStagnantProducts({int daysThreshold = 14}) async {
    final cutoff = DateTime.now().subtract(Duration(days: daysThreshold));
    final snapshot = await _db
        .collection('products')
        .where('createdAt', isLessThan: Timestamp.fromDate(cutoff))
        .where('isActive', isEqualTo: true)
        .where('soldCount', isEqualTo: 0)
        .get();

    return snapshot.docs.map((doc) => Product.fromFirestore(doc)).toList();
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
    if (originalPrice < 5000) {
      throw Exception('Flash sale haiwezi kuwa chini ya TSh 5,000');
    }

    final discountPercent = ((originalPrice - flashPrice) / originalPrice) * 100;
    final commission = flashPrice * 0.05;
    final sellerReceives = flashPrice - commission;
    final startTime = DateTime.now();
    final endTime = startTime.add(Duration(hours: durationHours));

    final docRef = await _db.collection('flash_sales').add({
      'productId': productId,
      'productName': productName,
      'productImage': productImage,
      'sellerId': sellerId,
      'sellerName': sellerName,
      'sellerPhone': sellerPhone,
      'location': location,
      'category': category,
      'originalPrice': originalPrice,
      'flashPrice': flashPrice,
      'discountPercent': discountPercent,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'maxQuantity': maxQuantity,
      'soldQuantity': 0,
      'status': 'active',
      'isActive': true,
      'aiReason': aiReason,
      'commission': commission,
      'sellerReceives': sellerReceives,
      'createdAt': FieldValue.serverTimestamp(),
    });

    _notif.sendNotification(
      userId: sellerId,
      title: '🔥 Flash Sale Imeundwa!',
      body: 'Bidhaa yako "$productName" iko kwenye Flash Sale! Bei mpya: TSh ${flashPrice.toStringAsFixed(0)} (discount ${discountPercent.toStringAsFixed(0)}%).',
      data: {
        'type': 'flash_sale',
        'flashSaleId': docRef.id,
        'productId': productId,
      },
    );

    final doc = await docRef.get();
    return FlashSale.fromFirestore(doc);
  }

  Future<void> incrementSold(String flashSaleId) async {
    await _db.collection('flash_sales').doc(flashSaleId).update({
      'soldQuantity': FieldValue.increment(1),
    });

    final doc = await _db.collection('flash_sales').doc(flashSaleId).get();
    final sale = FlashSale.fromFirestore(doc);

    if (sale.soldQuantity >= sale.maxQuantity) {
      await _db.collection('flash_sales').doc(flashSaleId).update({
        'status': 'completed',
      });
    }
  }

  Future<void> endFlashSale(String flashSaleId) async {
    await _db.collection('flash_sales').doc(flashSaleId).update({
      'status': 'ended',
      'isActive': false,
    });
  }

  Future<void> autoDetectStagnantProducts() async {
    final stagnant = await getStagnantProducts();

    for (final product in stagnant) {
      final existing = await _db
          .collection('flash_sales')
          .where('productId', isEqualTo: product.id)
          .where('status', isEqualTo: 'active')
          .get();

      if (existing.docs.isEmpty && product.price >= 5000) {
        final calc = _gemini.analyzeProductForDiscount(product);
        final recommendedDiscount = calc['recommendedDiscount'] as double;
        final flashPrice = calc['recommendedPrice'] as double;
        final minDiscount = calc['minDiscount'] as double;
        final maxDiscount = calc['maxDiscount'] as double;

        await createFlashSale(
          productId: product.id,
          productName: product.name,
          productImage: product.images.isNotEmpty ? product.images.first : '',
          sellerId: product.sellerId,
          sellerName: product.sellerName,
          sellerPhone: '',
          location: product.location,
          category: product.category,
          originalPrice: product.price,
          flashPrice: flashPrice,
          durationHours: 24,
          maxQuantity: product.stock,
          aiReason: 'AI imegundua bidhaa hii imekaa kwa muda mrefu bila kuuza. Discount ya $recommendedDiscount% ($minDiscount-$maxDiscount%) imependekezwa kwa sababu: ${calc['reason']}',
        );
      }
    }
  }
}
