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
  final List<Map<String, dynamic>>? imageMetadata;
  final String? videoUrl;
  final String sellerId;
  final String sellerName;
  final String category;
  final String subcategory;
  final String location;
  final String district;
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
  final bool sellerKycApproved;
  final String? barcode;
final String unit;
  final int minOrder;
  final int? maxOrder;

  Product({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    this.currency,
    required this.images,
    this.imageMetadata = const [],
    this.videoUrl,
    required this.sellerId,
    required this.sellerName,
    required this.category,
    required this.subcategory,
    required this.location,
    this.district = '',
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
    this.sellerKycApproved = false,
    this.barcode,
    this.unit = 'piece',
    this.minOrder = 1,
    this.maxOrder,
  });

  bool get isFeaturedValid =>
      isFeatured &&
      featuredUntil != null &&
      DateTime.now().isBefore(featuredUntil!);

  bool get isBoostedValid =>
      isBoosted &&
      boostedUntil != null &&
      DateTime.now().isBefore(boostedUntil!);

  static const String _r2PublicBase = 'https://media.soko-vibe.co.tz';

  /// Builds a [Product] from the v2 server DTO served by `/api/v1/products`.
  ///
  /// Server shape (PUBLIC_SELECT): `id, title, slug, description, price,
  /// originalPrice, currency, stock, status, condition, createdAt`,
  /// `seller{id,storeName,storeSlug}`, `media[{type, r2Key, ...}]`, and on
  /// detail an extra `category{name}` plus a `snapshot` carrying the legacy
  /// Firestore fields preserved by the migration mapper. `price` travels as a
  /// JSON number (BigInt→Number serialization on the server).
  factory Product.fromApi(Map<String, dynamic> json) {
    final seller = json['seller'];
    final sellerMap = seller is Map<String, dynamic>
        ? seller
        : (seller is List && seller.isNotEmpty ? seller[0] : null);
    final media = (json['media'] as List?) ?? const [];
    final snapshot = json['snapshot'] is Map<String, dynamic>
        ? json['snapshot'] as Map<String, dynamic>
        : <String, dynamic>{};
    final category = json['category'] is Map<String, dynamic>
        ? json['category'] as Map<String, dynamic>
        : <String, dynamic>{};

    List<String> images = [];
    for (final m in media) {
      if (m is Map<String, dynamic>) {
        final type = m['type'] ?? 'image';
        final key = m['r2Key'] ?? m['thumbnailR2Key'];
        if (key is String && key.isNotEmpty) {
          images.add(type == 'image'
              ? '$_r2PublicBase/$key'
              : (m['thumbnailR2Key'] is String &&
                      (m['thumbnailR2Key'] as String).isNotEmpty
                  ? '$_r2PublicBase/${m['thumbnailR2Key']}'
                  : '$_r2PublicBase/$key'));
        }
      }
    }
    if (images.isEmpty && snapshot['images'] is List) {
      images = List<String>.from(snapshot['images'] as List);
    }

    final createdAtRaw = json['createdAt'];
    DateTime createdAt;
    try {
      createdAt = DateTime.parse(createdAtRaw.toString()).toLocal();
    } catch (_) {
      createdAt = DateTime.now();
    }

    return Product(
      id: json['id']?.toString() ?? '',
      name: json['title']?.toString() ?? json['name']?.toString() ?? '',
      description: json['description']?.toString() ??
          snapshot['description']?.toString() ??
          '',
      price: (json['price'] ?? json['priceTzs'] ?? 0).toDouble(),
      currency: json['currency']?.toString() ?? 'TZS',
      images: images,
      videoUrl: json['videoUrl']?.toString() ?? snapshot['videoUrl']?.toString(),
      sellerId: json['sellerId']?.toString() ??
          sellerMap?['sellerId']?.toString() ??
          snapshot['sellerId']?.toString() ??
          '',
      sellerName: sellerMap?['storeName']?.toString() ??
          snapshot['sellerName']?.toString() ??
          '',
      sellerPhone: sellerMap?['sellerPhone']?.toString() ??
          snapshot['sellerPhone']?.toString(),
      category: category['name']?.toString() ??
          snapshot['category']?.toString() ??
          'General',
      subcategory: snapshot['subcategory']?.toString() ?? '',
      location: snapshot['location']?.toString() ?? '',
      district: snapshot['district']?.toString() ?? '',
      createdAt: createdAt,
      stock: (json['stock'] ?? 0) as int,
      rating: (json['rating'] ?? snapshot['rating'] ?? 0).toDouble(),
      reviewCount: json['reviewCount'] ?? snapshot['reviewCount'] ?? 0,
      soldCount: json['soldCount'] ?? snapshot['soldCount'] ?? 0,
      viewCount: json['viewCount'] ?? snapshot['viewCount'] ?? 0,
      isBoosted: json['isBoosted'] ?? snapshot['isBoosted'] ?? false,
      boostedUntil: json['boostedUntil'] != null
          ? DateTime.tryParse(json['boostedUntil'].toString())?.toLocal()
          : null,
      boostTier: json['boostTier']?.toString() ??
          snapshot['boostTier']?.toString() ??
          '',
      brand: snapshot['brand']?.toString(),
      condition: json['condition']?.toString() ??
          snapshot['condition']?.toString() ??
          'new',
      sellerKycApproved: snapshot['sellerKycApproved'] ?? false,
    );
  }

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
      imageMetadata: (data['imageMetadata'] as List?)
          ?.map((e) => Map<String, dynamic>.from(e))
          .toList(),
      videoUrl: data['videoUrl'] as String?,
      sellerId: data['sellerId'] ?? '',
      sellerName: data['sellerName'] ?? '',
      category: data['category'] ?? 'General',
      subcategory: data['subcategory'] ?? '',
      location: data['location'] as String? ?? '',
      district: data['district'] as String? ?? '',
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
      sellerKycApproved: data['sellerKycApproved'] ?? false,
      barcode: data['barcode'] as String?,
      unit: data['unit'] as String? ?? 'piece',
      minOrder: (data['minOrder'] ?? 1) as int,
      maxOrder: data['maxOrder'] as int?,
    );
  }

Map<String, dynamic> toMap() => {
    'name': name,
    'description': description,
    'price': price,
    'currency': currency ?? 'TZS',
    'images': images,
    'imageMetadata': imageMetadata,
    'videoUrl': videoUrl,
    'sellerId': sellerId,
    'sellerName': sellerName,
    'category': category,
    'subcategory': subcategory,
    'location': location,
    'district': district,
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
    'sellerKycApproved': sellerKycApproved,
    'barcode': barcode,
    'unit': unit,
    'minOrder': minOrder,
    'maxOrder': maxOrder,
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
