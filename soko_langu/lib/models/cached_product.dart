import 'package:hive/hive.dart';
import 'product_model.dart';

/// Lightweight product snapshot for offline caching via Hive.
///
/// Stores the fields needed to render a product card/list item.
/// Convert via [fromProduct] / [toProduct] to/from the full [Product] model.
class CachedProduct extends HiveObject {
  final String id;
  final String title;
  final double price;
  final String description;
  final String imageUrl;
  final String currency;
  final String location;
  final String sellerName;
  final String condition;
  final double rating;
  final int reviewCount;
  final DateTime createdAt;

  CachedProduct({
    required this.id,
    required this.title,
    required this.price,
    required this.description,
    required this.imageUrl,
    this.currency = 'TZS',
    this.location = '',
    this.sellerName = '',
    this.condition = 'new',
    this.rating = 0.0,
    this.reviewCount = 0,
    required this.createdAt,
  });

  factory CachedProduct.fromProduct(Product p) => CachedProduct(
        id: p.id,
        title: p.name,
        price: p.price,
        description: p.description,
        imageUrl: p.images.isNotEmpty ? p.images.first : '',
        currency: p.currency ?? 'TZS',
        location: p.location,
        sellerName: p.sellerName,
        condition: p.condition,
        rating: p.rating,
        reviewCount: p.reviewCount,
        createdAt: p.createdAt,
      );

  Product toProduct() => Product(
        id: id,
        name: title,
        price: price,
        description: description,
        images: imageUrl.isNotEmpty ? [imageUrl] : [],
        currency: currency,
        location: location,
        sellerId: '',
        sellerName: sellerName,
        category: '',
        subcategory: '',
        createdAt: createdAt,
        stock: 0,
        condition: condition,
        rating: rating,
        reviewCount: reviewCount,
      );
}

/// Manual TypeAdapter — no code generation needed.
class CachedProductAdapter extends TypeAdapter<CachedProduct> {
  @override
  final int typeId = 0;

  @override
  CachedProduct read(BinaryReader reader) {
    final fields = reader.readMap().cast<int, dynamic>();
    return CachedProduct(
      id: fields[0] as String,
      title: fields[1] as String,
      price: (fields[2] as num).toDouble(),
      description: fields[3] as String,
      imageUrl: fields[4] as String,
      currency: fields[5] as String? ?? 'TZS',
      location: fields[6] as String? ?? '',
      sellerName: fields[7] as String? ?? '',
      condition: fields[8] as String? ?? 'new',
      rating: (fields[9] as num?)?.toDouble() ?? 0.0,
      reviewCount: fields[10] as int? ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(fields[11] as int),
    );
  }

  @override
  void write(BinaryWriter writer, CachedProduct obj) {
    writer.writeMap({
      0: obj.id,
      1: obj.title,
      2: obj.price,
      3: obj.description,
      4: obj.imageUrl,
      5: obj.currency,
      6: obj.location,
      7: obj.sellerName,
      8: obj.condition,
      9: obj.rating,
      10: obj.reviewCount,
      11: obj.createdAt.millisecondsSinceEpoch,
    });
  }
}
