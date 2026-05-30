class ProductSearchResult {
  final String productId;
  final String productName;
  final String description;
  final String? firstImage;
  final double price;
  final String sellerId;
  final String sellerName;
  final String sellerPhone;
  final String location;
  final double rating;
  final int reviewCount;
  final String category;
  final String subcategory;
  final String? brand;
  final String condition;
  final int stock;
  final int soldCount;
  final int viewCount;
  final bool isWholesale;

  const ProductSearchResult({
    required this.productId,
    required this.productName,
    this.description = '',
    this.firstImage,
    required this.price,
    required this.sellerId,
    required this.sellerName,
    this.sellerPhone = '',
    this.location = '',
    this.rating = 0.0,
    this.reviewCount = 0,
    this.category = '',
    this.subcategory = '',
    this.brand,
    this.condition = 'new',
    this.stock = 0,
    this.soldCount = 0,
    this.viewCount = 0,
    this.isWholesale = false,
  });

  factory ProductSearchResult.fromFirestore(String id, Map<String, dynamic> data) {
    final images = List<String>.from(data['images'] ?? []);
    return ProductSearchResult(
      productId: id,
      productName: data['name']?.toString() ?? '',
      description: data['description']?.toString() ?? '',
      firstImage: images.isNotEmpty ? images.first : null,
      price: (data['price'] ?? 0).toDouble(),
      sellerId: data['sellerId']?.toString() ?? '',
      sellerName: data['sellerName']?.toString() ?? '',
      sellerPhone: data['sellerPhone']?.toString() ?? '',
      location: data['location']?.toString() ?? '',
      rating: (data['rating'] ?? 0).toDouble(),
      reviewCount: (data['reviewCount'] as num?)?.toInt() ?? 0,
      category: data['category']?.toString() ?? '',
      subcategory: data['subcategory']?.toString() ?? '',
      brand: data['brand']?.toString(),
      condition: data['condition']?.toString() ?? 'new',
      stock: (data['stock'] as num?)?.toInt() ?? 0,
      soldCount: (data['soldCount'] as num?)?.toInt() ?? 0,
      viewCount: (data['viewCount'] as num?)?.toInt() ?? 0,
      isWholesale: data['isWholesale'] == true,
    );
  }

  String toContextBlock(int index, {String currencySymbol = 'TSh'}) {
    final buffer = StringBuffer()
      ..writeln('--- BIDHAA #$index | ✅ IPO KWENYE SOKO LANGU (chanzo: database ya app) ---')
      ..writeln('ID: $productId')
      ..writeln('Jina: $productName')
      ..writeln('Maelezo: $description')
      ..writeln('Bei: $currencySymbol ${price.toStringAsFixed(0)}')
      ..writeln('Muuzaji ID: $sellerId')
      ..writeln('Muuzaji: $sellerName')
      ..writeln('Simu ya muuzaji: ${sellerPhone.isNotEmpty ? sellerPhone : "haijasajiliwa"}')
      ..writeln('Eneo/Mahali: ${location.isNotEmpty ? location : "haijasajiliwa"}');
    if (brand != null && brand!.isNotEmpty) buffer.writeln('Brand: $brand');
    buffer
      ..writeln('Kategoria: $category')
      ..writeln('Hali: $condition')
      ..writeln('Stock: $stock')
      ..writeln('Imeuzwa: $soldCount')
      ..writeln(
        'Rating: ${rating > 0 ? "${rating.toStringAsFixed(1)}/5 ($reviewCount maoni)" : "bado hakuna rating"}',
      );
    if (firstImage != null) buffer.writeln('Picha (URL): $firstImage');
    if (isWholesale) buffer.writeln('Bei ya jumla: Ndiyo');
    return buffer.toString();
  }
}
