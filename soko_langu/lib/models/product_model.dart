import 'package:cloud_firestore/cloud_firestore.dart';

class ProductVariant {
  final String id;
  final String name;
  final String value;
  final double? priceAdjustment;
  final int stock;

  ProductVariant({
    required this.id,
    required this.name,
    required this.value,
    this.priceAdjustment,
    required this.stock,
  });

  factory ProductVariant.fromMap(Map<String, dynamic> map, String id) {
    return ProductVariant(
      id: id,
      name: map['name'] ?? '',
      value: map['value'] ?? '',
      priceAdjustment: map['priceAdjustment']?.toDouble(),
      stock: map['stock'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'value': value,
    'priceAdjustment': priceAdjustment,
    'stock': stock,
  };
}

class WholesaleTier {
  final int minQuantity;
  final double pricePerUnit;

  WholesaleTier({required this.minQuantity, required this.pricePerUnit});

  factory WholesaleTier.fromMap(Map<String, dynamic> map) {
    return WholesaleTier(
      minQuantity: map['minQuantity'] ?? 0,
      pricePerUnit: (map['pricePerUnit'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
    'minQuantity': minQuantity,
    'pricePerUnit': pricePerUnit,
  };
}

class Product {
  final String id;
  final String name;
  final String description;
  final double price;
  final String? currency;
  final List<String> images;
  final String sellerId;
  final String sellerName;
  final String category;
  final String subcategory;
  final String location;
  final DateTime createdAt;
  final int stock;
  final bool isWholesale;
  final List<WholesaleTier> wholesaleTiers;
  final List<ProductVariant> variants;
  final double rating;
  final int reviewCount;
  final int soldCount;
  final int viewCount;
  final Map<String, dynamic> attributes;
  final bool isActive;
  final bool isFeatured;
  final DateTime? featuredUntil;
  final bool isBoosted;
  final DateTime? boostedUntil;
  final String boostTier;
  final String? brand;
  final String? sellerPhone;
  final String condition;

  Product({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    this.currency,
    required this.images,
    required this.sellerId,
    required this.sellerName,
    required this.category,
    required this.subcategory,
    required this.location,
    required this.createdAt,
    required this.stock,
    this.isWholesale = false,
    this.wholesaleTiers = const [],
    this.variants = const [],
    this.rating = 0.0,
    this.reviewCount = 0,
    this.soldCount = 0,
    this.viewCount = 0,
    this.attributes = const {},
    this.isActive = true,
    this.isFeatured = false,
    this.featuredUntil,
    this.isBoosted = false,
    this.boostedUntil,
    this.boostTier = '',
    this.brand,
    this.sellerPhone,
    this.condition = 'new',
  });

  bool get isFeaturedValid =>
      isFeatured &&
      featuredUntil != null &&
      DateTime.now().isBefore(featuredUntil!);

  bool get isBoostedValid =>
      isBoosted &&
      boostedUntil != null &&
      DateTime.now().isBefore(boostedUntil!);

  factory Product.fromFirestore(DocumentSnapshot doc) {
    final dataRaw = doc.data();
    if (dataRaw == null) throw Exception('Document data is null');
    Map<String, dynamic> data = dataRaw as Map<String, dynamic>;

    List<ProductVariant> variants = [];
    if (data['variants'] != null) {
      for (var v in (data['variants'] as List)) {
        if (v is Map<String, dynamic>) {
          variants.add(ProductVariant.fromMap(v, v['id'] ?? ''));
        }
      }
    }

    List<WholesaleTier> wholesaleTiers = [];
    if (data['wholesaleTiers'] != null) {
      for (var t in (data['wholesaleTiers'] as List)) {
        if (t is Map<String, dynamic>) {
          wholesaleTiers.add(WholesaleTier.fromMap(t));
        }
      }
    }

    return Product(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      price: (data['price'] ?? 0).toDouble(),
      currency: data['currency'] ?? 'TZS',
      images: List<String>.from(data['images'] ?? []),
      sellerId: data['sellerId'] ?? '',
      sellerName: data['sellerName'] ?? '',
      category: data['category'] ?? 'General',
      subcategory: data['subcategory'] ?? '',
      location: data['location'] ?? 'Tanzania',
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      stock: data['stock'] ?? 0,
      isWholesale: data['isWholesale'] ?? false,
      wholesaleTiers: wholesaleTiers,
      variants: variants,
      rating: (data['rating'] ?? 0).toDouble(),
      reviewCount: data['reviewCount'] ?? 0,
      soldCount: data['soldCount'] ?? 0,
      viewCount: data['viewCount'] ?? 0,
      attributes: Map<String, dynamic>.from(data['attributes'] ?? {}),
      isActive: data['isActive'] ?? true,
      isFeatured: data['isFeatured'] ?? false,
      featuredUntil: data['featuredUntil'] is Timestamp
          ? (data['featuredUntil'] as Timestamp).toDate()
          : null,
      isBoosted: data['isBoosted'] ?? data['isFeatured'] ?? false,
      boostedUntil: data['boostedUntil'] is Timestamp
          ? (data['boostedUntil'] as Timestamp).toDate()
          : (data['featuredUntil'] is Timestamp
              ? (data['featuredUntil'] as Timestamp).toDate()
              : null),
      boostTier: data['boostTier'] as String? ?? '',
      brand: data['brand'],
      sellerPhone: data['sellerPhone'] as String?,
      condition: data['condition'] ?? 'new',
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'description': description,
    'price': price,
    'currency': currency ?? 'TZS',
    'images': images,
    'sellerId': sellerId,
    'sellerName': sellerName,
    'category': category,
    'subcategory': subcategory,
    'location': location,
    'createdAt': FieldValue.serverTimestamp(),
    'stock': stock,
    'isWholesale': isWholesale,
    'wholesaleTiers': wholesaleTiers.map((t) => t.toMap()).toList(),
    'variants': variants.map((v) => v.toMap()).toList(),
    'rating': rating,
    'reviewCount': reviewCount,
    'soldCount': soldCount,
    'viewCount': viewCount,
    'attributes': attributes,
    'isActive': isActive,
    'isFeatured': isFeatured,
    'featuredUntil': featuredUntil != null
        ? Timestamp.fromDate(featuredUntil!)
        : null,
    'isBoosted': isBoosted,
    'boostedUntil': boostedUntil != null
        ? Timestamp.fromDate(boostedUntil!)
        : null,
    'boostTier': boostTier,
    'brand': brand,
    'sellerPhone': sellerPhone,
    'condition': condition,
  };

  double getWholesalePrice(int quantity) {
    if (!isWholesale || wholesaleTiers.isEmpty) return price;
    WholesaleTier? applicableTier;
    for (var tier in wholesaleTiers) {
      if (quantity >= tier.minQuantity) {
        applicableTier = tier;
      }
    }
    return applicableTier?.pricePerUnit ?? price;
  }
}
