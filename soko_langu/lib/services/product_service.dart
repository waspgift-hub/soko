import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/product_model.dart';
import 'cloudinary_service.dart';
import 'fraud_prevention_service.dart';
import 'api_config.dart';
import '../utils/network_error.dart';

const List<String> knownBrands = [
  'Nike', 'Adidas', 'Samsung', 'Apple', 'Sony', 'LG', 'Toyota', 'Hp', 'Dell',
  'Other', 'Others',
];

String _normalizeBrand(String? brand) {
  final trimmed = brand?.trim() ?? '';
  if (trimmed.isEmpty) return '';
  return trimmed.split(' ').map((word) {
    if (word.isEmpty) return '';
    return word[0].toUpperCase() + word.substring(1).toLowerCase();
  }).join(' ');
}

List<String> _generateSearchKeywords(String name, String description, String category, String? brand) {
  final words = <String>{};
  final text = '$name $description $category ${brand ?? ''}';
  for (final part in text.split(RegExp(r'[\s,.-]+'))) {
    final w = part.trim().toLowerCase();
    if (w.length >= 2) words.add(w);
  }
  return words.toList();
}

String getThumbnailUrl(String imageUrl, {int width = 300}) {
  try {
    final uri = Uri.parse(imageUrl);
    if (uri.host.contains('cloudinary.com')) {
      final segments = uri.pathSegments;
      final uploadIdx = segments.indexOf('upload');
      if (uploadIdx >= 0 && uploadIdx + 1 < segments.length) {
        final before = segments.sublist(0, uploadIdx + 1).join('/');
        final after = segments.sublist(uploadIdx + 1).join('/');
        return '${uri.scheme}://${uri.host}/$before/w_$width,c_fill,q_auto,f_auto/$after';
      }
    }
  } catch (_) {}
  return imageUrl;
}

void _sortByBoost(List<Product> products) {
  products.sort((a, b) {
    final aBoosted = a.isBoostedValid ? 0 : 1;
    final bBoosted = b.isBoostedValid ? 0 : 1;
    final f = aBoosted.compareTo(bBoosted);
    if (f != 0) return f;
    return b.createdAt.compareTo(a.createdAt);
  });
}

class ProductService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<String> uploadImage(XFile xfile) async {
    return CloudinaryService.uploadImage(xfile, folder: 'products');
  }

  Future<void> addProduct({
    required String name,
    required String description,
    required double price,
    required String category,
    required String subcategory,
    required String currency,
    required int stock,
    required List<XFile> imageFiles,
    String location = 'Tanzania',
    bool isWholesale = false,
    List<Map<String, dynamic>>? wholesaleTiers,
    List<Map<String, dynamic>>? variants,
    Map<String, dynamic>? attributes,
    String? brand,
    String condition = 'new',
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception("User not logged in");

      // Refresh session so Firestore rules see a valid auth token
      await user.reload();
      await user.getIdToken(true);

      final userDoc = await _db.collection('users').doc(user.uid).get();
      final userData = userDoc.data();
      final kycApproved = userData?['kyc']?['approved'] == true;
      if (!kycApproved) {
        throw NetworkError(
          message: "KYC not approved",
          userMessage: "KYC: Tafadhali kamilisha KYC verification kabla ya kuuza bidhaa",
          originalError: Exception("KYC not approved"),
        );
      }

      List<String> imageUrls = [];
      for (var file in imageFiles) {
        final url = await uploadImage(file);
        imageUrls.add(url);
      }

      String sellerName = user.displayName ?? user.email ?? 'Anonymous';
      String sellerPhone = '';
      bool sellerKycApproved = true;

      if (userDoc.exists) {
        final data = userDoc.data()!;
        sellerPhone = data['phone'] as String? ?? '';
      }

      await _writeProduct(
        user.uid, name, description, price, currency, imageUrls,
        category, subcategory, stock, sellerName, sellerPhone,
        sellerKycApproved, isWholesale, wholesaleTiers, variants,
        attributes, brand, condition, location,
      );
    } catch (e) {
      throw NetworkError(
          message: "Failed to add product: $e",
          userMessage: translateError(e),
          originalError: e,
        );
    }
  }

  Future<String> _writeProduct(
    String uid,
    String name,
    String description,
    double price,
    String currency,
    List<String> imageUrls,
    String category,
    String subcategory,
    int stock,
    String sellerName,
    String sellerPhone,
    bool sellerKycApproved,
    bool isWholesale,
    List<Map<String, dynamic>>? wholesaleTiers,
    List<Map<String, dynamic>>? variants,
    Map<String, dynamic>? attributes,
    String? brand,
    String condition,
    String location,
  ) async {
    final searchKeywords = _generateSearchKeywords(name, description, category, brand);

    final docRef = await _db.collection("products").add({
      "name": name,
      "searchName": name.toLowerCase(),
      "description": description,
      "price": price,
      "currency": currency,
      "images": imageUrls,
      "sellerId": uid,
      "sellerName": sellerName,
      "sellerPhone": sellerPhone,
      "category": category,
      "subcategory": subcategory,
      "location": location,
      "stock": stock,
      "isWholesale": isWholesale,
      "wholesaleTiers": wholesaleTiers ?? [],
      "variants": variants ?? [],
      "attributes": attributes ?? {},
      "brand": _normalizeBrand(brand),
      "condition": condition,
      "rating": 0.0,
      "reviewCount": 0,
      "soldCount": 0,
      "isActive": true,
      "isFeatured": false,
      "featuredUntil": null,
      "sellerKycApproved": sellerKycApproved,
      "searchKeywords": searchKeywords,
      "createdAt": FieldValue.serverTimestamp(),
    });

    final fraud = FraudPreventionService();
    await fraud.checkNewSeller(uid, sellerName);
    final productCount = await _db.collection('products')
        .where('sellerId', isEqualTo: uid)
        .count().get();
    await fraud.checkSuspiciousListing(
      sellerId: uid,
      sellerName: sellerName,
      productId: docRef.id,
      productName: name,
      price: price,
      sellerProductCount: productCount.count ?? 0,
    );
    return docRef.id;
  }

  /// Firestore paginated query — returns products and the last document cursor.
  Future<(List<Product>, DocumentSnapshot<Map<String, dynamic>>?)> fetchProducts({
    int limit = 30,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    var query = _db
        .collection("products")
        .where('isActive', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(limit);
    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }
    final snapshot = await query.get();
    final products = snapshot.docs
        .map((doc) => Product.fromFirestore(doc))
        .toList();
    final lastDoc = snapshot.docs.isEmpty ? null : snapshot.docs.last;
    return (products, lastDoc);
  }

  /// Paginated query for a specific brand.
  Future<List<Product>> fetchProductsByBrand(String brand, {int limit = 30}) async {
    if (brand == 'Others') {
      return fetchProductsByBrandOthers(limit: limit);
    }
    final snapshot = await _db
        .collection("products")
        .where('isActive', isEqualTo: true)
        .where("brand", isEqualTo: brand)
        .limit(limit)
        .get();
    final products = snapshot.docs
        .map((doc) => Product.fromFirestore(doc))
        .toList();
    _sortByBoost(products);
    return products;
  }

  /// Catch-all for brands not in the known list.
  Future<List<Product>> fetchProductsByBrandOthers({int limit = 30}) async {
    final snapshot = await _db
        .collection("products")
        .where('isActive', isEqualTo: true)
        .limit(limit * 3)
        .get();
    final products = snapshot.docs
        .map((doc) => Product.fromFirestore(doc))
        .where((p) => p.brand != null && p.brand!.isNotEmpty && !knownBrands.contains(p.brand))
        .take(limit)
        .toList();
    _sortByBoost(products);
    return products;
  }

  /// Paginated query for a category + optional subcategory.
  Future<List<Product>> fetchProductsByCategory(
    String category, {
    String? subcategory,
    int limit = 30,
  }) async {
    var query = _db
        .collection("products")
        .where('isActive', isEqualTo: true)
        .where("category", isEqualTo: category)
        .orderBy('createdAt', descending: true)
        .limit(limit);
    if (subcategory != null) {
      query = query.where("subcategory", isEqualTo: subcategory);
    }
    final snapshot = await query.get();
    return snapshot.docs.map((doc) => Product.fromFirestore(doc)).toList();
  }

  /// Alias for [getProductById] — used by [ProductRepository].
  Future<Product?> fetchProduct(String id) => getProductById(id);

  /// Real-time stream wrapper — used by [ProductRepository].
  Stream<List<Product>> watchProductsRealtime({int limit = 50}) {
    return _db
        .collection("products")
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
      final products = snapshot.docs
          .map((doc) => Product.fromFirestore(doc))
          .toList();
      products.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return products.take(limit).toList();
    });
  }

  Stream<List<Product>> getProducts({int limitAmt = 30}) {
    return _db
        .collection("products")
        .snapshots()
        .map((snapshot) {
      final products = snapshot.docs
          .map((doc) => Product.fromFirestore(doc))
          .where((p) => p.isActive)
          .toList();
      products.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _sortByBoost(products);
      return products.take(limitAmt).toList();
    });
  }

  Stream<List<Product>> getProductsByCategory(String category) {
    return _db
        .collection("products")
        .where("category", isEqualTo: category)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
          final products = snapshot.docs
              .map((doc) => Product.fromFirestore(doc))
              .toList();
          _sortByBoost(products);
          return products;
        });
  }

  Stream<List<Product>> getProductsByCategoryAndSubcategory(
    String category,
    String subcategory,
  ) {
    return _db
        .collection("products")
        .where("category", isEqualTo: category)
        .where("subcategory", isEqualTo: subcategory)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
          final products = snapshot.docs
              .map((doc) => Product.fromFirestore(doc))
              .toList();
          _sortByBoost(products);
          return products;
        });
  }

  Stream<List<Product>> searchProducts(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return Stream.value([]);
    final words = q.split(RegExp(r'\s+')).where((w) => w.length >= 2).toList();
    if (words.isEmpty) return Stream.value([]);

    Stream<List<Product>> stream;
    if (words.length == 1) {
      stream = _db.collection("products")
          .where('searchKeywords', arrayContains: words[0])
          .limit(100)
          .snapshots()
          .map((snap) => snap.docs.map((doc) => Product.fromFirestore(doc)).toList());
    } else {
      stream = _db.collection("products")
          .where('searchKeywords', arrayContainsAny: words.take(10).toList())
          .limit(100)
          .snapshots()
          .map((snap) => snap.docs.map((doc) => Product.fromFirestore(doc)).toList());
    }

    return stream.map((products) {
      final filtered = products
          .where((p) => p.isActive && words.every((w) =>
            p.name.toLowerCase().contains(w) ||
            p.description.toLowerCase().contains(w)))
          .toList();
      _sortByBoost(filtered);
      return filtered;
    });
  }

  Stream<List<Product>> searchByNameStream(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return Stream.value([]);
    return _db
        .collection("products")
        .where('searchName', isGreaterThanOrEqualTo: q)
        .where('searchName', isLessThanOrEqualTo: '$q\uf8ff')
        .orderBy('searchName')
        .limit(30)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => Product.fromFirestore(doc))
          .where((p) => p.isActive)
          .toList();
    });
  }

  Future<List<Product>> searchProductsOnce(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    final words = q.split(RegExp(r'\s+')).where((w) => w.length >= 2).toList();
    if (words.isEmpty) return [];

    var products = <Product>[];
    try {
      if (words.length == 1) {
        final snap = await _db.collection("products")
            .where('searchKeywords', arrayContains: words[0])
            .limit(100)
            .get();
        products = snap.docs.map((doc) => Product.fromFirestore(doc)).toList();
      } else {
        final snap = await _db.collection("products")
            .where('searchKeywords', arrayContainsAny: words.take(10).toList())
            .limit(100)
            .get();
        products = snap.docs.map((doc) => Product.fromFirestore(doc)).toList();
      }
      products = products
          .where((p) => p.isActive && words.every((w) =>
            p.name.toLowerCase().contains(w) ||
            p.description.toLowerCase().contains(w)))
          .toList();
      _sortByBoost(products);
    } catch (e) {
      debugPrint('searchProductsOnce error: $e');
    }
    return products;
  }

  Stream<List<Product>> getProductsByBrand(String brand) {
    if (brand == 'Others') {
      return _db
          .collection("products")
          .where('isActive', isEqualTo: true)
          .snapshots()
          .map((snapshot) {
            final products = snapshot.docs
                .map((doc) => Product.fromFirestore(doc))
                .where((p) => p.brand != null && p.brand!.isNotEmpty && !knownBrands.contains(p.brand))
                .toList();
            _sortByBoost(products);
            return products;
          });
    }
    return _db
        .collection("products")
        .where("brand", isEqualTo: brand)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
          final products = snapshot.docs
              .map((doc) => Product.fromFirestore(doc))
              .toList();
          _sortByBoost(products);
          return products;
        });
  }

  Stream<List<Product>> getMyProducts() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    return _db
        .collection("products")
        .where("sellerId", isEqualTo: user.uid)
        .snapshots()
        .map((snapshot) {
          final products = snapshot.docs
              .map((doc) => Product.fromFirestore(doc))
              .toList();
          products.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return products;
        });
  }

  Future<Product?> getProductById(String productId) async {
    try {
      final doc = await _db.collection("products").doc(productId).get();
      if (doc.exists) {
        return Product.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      throw NetworkError(
          message: "Failed to get product: $e",
          userMessage: translateError(e),
          originalError: e,
        );
    }
  }

  Future<void> updateProduct({
    required String productId,
    String? name,
    String? description,
    double? price,
    String? category,
    String? subcategory,
    int? stock,
    bool? isWholesale,
    List<Map<String, dynamic>>? wholesaleTiers,
    List<Map<String, dynamic>>? variants,
    String? brand,
    String? condition,
    List<String>? existingImages,
    List<XFile>? newImages,
    String? location,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw NetworkError(
        message: 'Not authenticated',
        userMessage: 'Please log in to continue.',
      );
      await user.reload();
      await user.getIdToken(true);

      Map<String, dynamic> data = {};
      bool needsKeywordUpdate = false;

      if (name != null) { data["name"] = name; data["searchName"] = name.toLowerCase(); needsKeywordUpdate = true; }
      if (description != null) { data["description"] = description; needsKeywordUpdate = true; }
      if (category != null) { data["category"] = category; needsKeywordUpdate = true; }
      if (brand != null) { data["brand"] = _normalizeBrand(brand); needsKeywordUpdate = true; }
      if (price != null) data["price"] = price;
      if (subcategory != null) data["subcategory"] = subcategory;
      if (stock != null) data["stock"] = stock;
      if (isWholesale != null) data["isWholesale"] = isWholesale;
      if (wholesaleTiers != null) data["wholesaleTiers"] = wholesaleTiers;
      if (variants != null) data["variants"] = variants;
      if (condition != null) data["condition"] = condition;
      if (location != null) data["location"] = location;

      if (existingImages != null || newImages != null) {
        List<String> allImages = existingImages ?? [];
        if (newImages != null) {
          for (var file in newImages) {
            final url = await uploadImage(file);
            allImages.add(url);
          }
        }
        data["images"] = allImages;
      }

      if (needsKeywordUpdate) {
        final current = await _db.collection("products").doc(productId).get();
        final cur = current.data() ?? {};
        data["searchKeywords"] = _generateSearchKeywords(
          name ?? cur["name"] as String? ?? '',
          description ?? cur["description"] as String? ?? '',
          category ?? cur["category"] as String? ?? '',
          brand ?? cur["brand"] as String?,
        );
      }

      await _db.collection("products").doc(productId).update(data);
    } catch (e) {
      throw NetworkError(
          message: "Update failed: $e",
          userMessage: translateError(e),
          originalError: e,
        );
    }
  }

  Future<void> deleteProduct(String productId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not authenticated');

      final token = await user.getIdToken();
      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/api/products/$productId'),
        headers: { 'Authorization': 'Bearer $token' },
      );

      if (response.statusCode != 200) {
        final body = jsonDecode(response.body);
        throw Exception(body['error'] ?? 'Delete failed');
      }
    } catch (e) {
      throw NetworkError(
          message: "Delete failed: $e",
          userMessage: translateError(e),
          originalError: e,
        );
    }
  }

  Future<void> updateProductRating(String productId, double newRating) async {
    try {
      final product = await getProductById(productId);
      if (product == null) return;

      final newReviewCount = product.reviewCount + 1;
      final newAverageRating =
          ((product.rating * product.reviewCount) + newRating) / newReviewCount;

      await _db.collection("products").doc(productId).update({
        "rating": newAverageRating,
        "reviewCount": newReviewCount,
      });
    } catch (e) {
      throw NetworkError(
          message: "Failed to update rating: $e",
          userMessage: translateError(e),
          originalError: e,
        );
    }
  }

  Stream<List<Product>> getFeaturedProducts() {
    return _db
        .collection("products")
        .where("isBoosted", isEqualTo: true)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
      final products = snapshot.docs
          .map((doc) => Product.fromFirestore(doc))
          .where((p) => p.isBoostedValid)
          .toList();
      products.sort((a, b) {
        final tierOrder = (b.boostTier).compareTo(a.boostTier);
        if (tierOrder != 0) return tierOrder;
        return b.createdAt.compareTo(a.createdAt);
      });
      return products;
    });
  }

  Future<void> incrementViewCount(String productId) async {
    try {
      await _db.collection("products").doc(productId).update({
        "viewCount": FieldValue.increment(1),
      });
    } catch (e) {
      // Silent
    }
  }

  Future<void> incrementSoldCount(String productId, int quantity) async {
    try {
      await _db.collection("products").doc(productId).update({
        "soldCount": FieldValue.increment(quantity),
      });
    } catch (e) {
      throw NetworkError(
          message: "Failed to update sold count: $e",
          userMessage: translateError(e),
          originalError: e,
        );
    }
  }
}
