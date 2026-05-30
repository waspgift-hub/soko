class CartItem {
  final String productId;
  final String name;
  final String image;
  final double price;
  final String sellerId;
  final String sellerName;
  int quantity;

  CartItem({
    required this.productId,
    required this.name,
    this.image = '',
    required this.price,
    required this.sellerId,
    this.sellerName = '',
    this.quantity = 1,
  });

  double get totalPrice => price * quantity;

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'name': name,
    'image': image,
    'price': price,
    'sellerId': sellerId,
    'sellerName': sellerName,
    'quantity': quantity,
  };

  factory CartItem.fromMap(Map<String, dynamic> map) => CartItem(
    productId: map['productId'] ?? '',
    name: map['name'] ?? '',
    image: map['image'] ?? '',
    price: (map['price'] ?? 0).toDouble(),
    sellerId: map['sellerId'] ?? '',
    sellerName: map['sellerName'] ?? '',
    quantity: map['quantity'] ?? 1,
  );
}
