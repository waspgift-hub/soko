import '../../models/product_model.dart';

/// Minimal cart line — one product + quantity + the unit price the
/// buyer actually accepted (flash/wholesale aware from details).
class CartItem {
  final String productId;
  final String sellerId;
  final String sellerName;
  final String productName;
  final String productImage;
  final int quantity;
  final double unitPrice;
  final String? variantId;
  final int stock;

  const CartItem({
    required this.productId,
    required this.sellerId,
    required this.sellerName,
    required this.productName,
    required this.productImage,
    required this.quantity,
    required this.unitPrice,
    this.variantId,
    this.stock = 999999,
  });

  double get lineTotal => unitPrice * quantity;

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'sellerId': sellerId,
        'sellerName': sellerName,
        'productName': productName,
        'productImage': productImage,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'variantId': variantId,
        'stock': stock,
      };

  factory CartItem.fromMap(Map<String, dynamic> map) => CartItem(
        productId: map['productId'] as String? ?? '',
        sellerId: map['sellerId'] as String? ?? '',
        sellerName: map['sellerName'] as String? ?? '',
        productName: map['productName'] as String? ?? '',
        productImage: map['productImage'] as String? ?? '',
        quantity: (map['quantity'] as num?)?.toInt() ?? 1,
        unitPrice: (map['unitPrice'] as num?)?.toDouble() ?? 0,
        variantId: map['variantId'] as String?,
        stock: (map['stock'] as num?)?.toInt() ?? 999999,
      );
}

extension ProductToCartItem on Product {
  CartItem toCartItem({required int quantity, String? variantId, double? unitPrice}) {
    return CartItem(
      productId: id,
      sellerId: sellerId,
      sellerName: sellerName,
      productName: name,
      productImage: images.isNotEmpty ? images.first : '',
      quantity: quantity,
      unitPrice: unitPrice ?? price,
      variantId: variantId,
      stock: stock,
    );
  }
}
