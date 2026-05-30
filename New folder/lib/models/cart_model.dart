class CartItem {
  final String productId;
  final String name;
  final double price;
  final String? image;
  final int quantity;
  final String sellerId;
  final Map<String, dynamic>? selectedVariant;

  CartItem({
    required this.productId,
    required this.name,
    required this.price,
    this.image,
    required this.quantity,
    required this.sellerId,
    this.selectedVariant,
  });

  double get totalPrice => price * quantity;

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'name': name,
    'price': price,
    'image': image,
    'quantity': quantity,
    'sellerId': sellerId,
    'selectedVariant': selectedVariant,
  };

  factory CartItem.fromMap(Map<String, dynamic> map) {
    return CartItem(
      productId: map['productId'] ?? '',
      name: map['name'] ?? '',
      price: (map['price'] ?? 0).toDouble(),
      image: map['image'],
      quantity: map['quantity'] ?? 1,
      sellerId: map['sellerId'] ?? '',
      selectedVariant: map['selectedVariant'],
    );
  }
}
