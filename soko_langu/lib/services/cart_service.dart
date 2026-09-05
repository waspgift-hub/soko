import 'package:hive_flutter/hive_flutter.dart';
import '../../models/product_model.dart';
import '../../models/cart_item.dart';

/// Cart persistence: has its own encrypted box, groups by seller,
/// and leaves the backend as source of truth for price/stock/escrow.
class CartService {
  static const _boxName = 'cart_items';
  static Box<dynamic>? _box;

  static Future<void> init() async {
    if (Hive.isBoxOpen(_boxName)) {
      _box = Hive.box(_boxName);
      return;
    }
    _box = await Hive.openBox(_boxName);
  }

  static Box<dynamic> _getBox() {
    final box = _box;
    if (box == null || !box.isOpen) {
      throw StateError('CartService.init() must be called before use');
    }
    return box;
  }

  List<CartItem> get items {
    return _getBox().values.map((raw) {
      final map = Map<String, dynamic>.from(raw as Map);
      return CartItem.fromMap(map);
    }).toList();
  }

  /// Emits freshly-parsed items whenever the Hive box changes so the cart
  /// badge and the cart screen stay live without manual refresh.
  Stream<List<CartItem>> watch() =>
      _getBox().watch().map((_) => items);

  int get count => items.length;

  Future<void> add({
    required Product product,
    required int quantity,
    String? variantId,
    double? unitPrice,
  }) async {
    final key = '${product.id}::${variantId ?? ''}';
    final existing = _getBox().get(key);
    if (existing != null) {
      final prev = CartItem.fromMap(Map<String, dynamic>.from(existing as Map));
      final nextQty = prev.quantity + quantity;
      await _getBox().put(
        key,
        CartItem(
          productId: product.id,
          sellerId: product.sellerId,
          sellerName: product.sellerName,
          productName: product.name,
          productImage: product.images.isNotEmpty ? product.images.first : '',
          quantity: nextQty,
          unitPrice: unitPrice ?? prev.unitPrice,
          variantId: variantId ?? prev.variantId,
          stock: product.stock,
        ).toMap(),
      );
      return;
    }
    await _getBox().put(
      key,
      CartItem(
        productId: product.id,
        sellerId: product.sellerId,
        sellerName: product.sellerName,
        productName: product.name,
        productImage: product.images.isNotEmpty ? product.images.first : '',
        quantity: quantity,
        unitPrice: unitPrice ?? product.price,
        variantId: variantId,
        stock: product.stock,
      ).toMap(),
    );
  }

  Future<void> updateQty(String productId, String? variantId, int quantity) async {
    final key = '$productId::${variantId ?? ''}';
    final raw = _getBox().get(key);
    if (raw == null) return;
    final item = CartItem.fromMap(Map<String, dynamic>.from(raw as Map));
    await _getBox().put(
      key,
      CartItem(
        productId: item.productId,
        sellerId: item.sellerId,
        sellerName: item.sellerName,
        productName: item.productName,
        productImage: item.productImage,
        quantity: quantity,
        unitPrice: item.unitPrice,
        variantId: item.variantId,
        stock: item.stock,
      ).toMap(),
    );
  }

  Future<void> remove(String productId, String? variantId) async {
    final key = '$productId::${variantId ?? ''}';
    await _getBox().delete(key);
  }

  Future<void> clearSeller(String sellerId) async {
    for (final key in _getBox().keys.toList()) {
      final raw = _getBox().get(key);
      if (raw == null) continue;
      final map = Map<String, dynamic>.from(raw as Map);
      if (map['sellerId'] == sellerId) await _getBox().delete(key);
    }
  }

  Future<void> clearAll() async {
    await _getBox().clear();
  }

  Map<String, List<CartItem>> grouped() {
    final groups = <String, List<CartItem>>{};
    for (final item in items) {
      groups.putIfAbsent(item.sellerId, () => []).add(item);
    }
    return groups;
  }

  double get subtotal =>
      items.fold(0.0, (sum, e) => sum + e.unitPrice * e.quantity);
}
