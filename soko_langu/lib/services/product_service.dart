import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/product_model.dart';
import 'cloudinary_service.dart';
import 'fraud_prevention_service.dart';
import '../utils/network_error.dart';

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

      List<String> imageUrls = [];
      for (var file in imageFiles) {
        final url = await uploadImage(file);
        imageUrls.add(url);
      }

      String sellerName = user.displayName ?? user.email ?? 'Anonymous';
      String sellerPhone = '';

      final userDoc = await _db.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        final data = userDoc.data()!;
        sellerPhone = data['phone'] as String? ?? '';
      }

      final docRef = await _db.collection("products").add({
        "name": name,
        "description": description,
        "price": price,
        "currency": currency,
        "images": imageUrls,
        "sellerId": user.uid,
        "sellerName": sellerName,
        "sellerPhone": sellerPhone,
        "category": category,
        "subcategory": subcategory,
        "location": "Tanzania",
        "stock": stock,
        "isWholesale": isWholesale,
        "wholesaleTiers": wholesaleTiers ?? [],
        "variants": variants ?? [],
        "attributes": attributes ?? {},
        "brand": brand,
        "condition": condition,
        "rating": 0.0,
        "reviewCount": 0,
        "soldCount": 0,
        "isActive": true,
        "isFeatured": false,
        "featuredUntil": null,
        "createdAt": FieldValue.serverTimestamp(),
      });

      final fraud = FraudPreventionService();
      await fraud.checkNewSeller(user.uid, sellerName);
      final productCount = await _db.collection('products')
          .where('sellerId', isEqualTo: user.uid)
          .count().get();
      await fraud.checkSuspiciousListing(
        sellerId: user.uid,
        sellerName: sellerName,
        productId: docRef.id,
        productName: name,
        price: price,
        sellerProductCount: productCount.count ?? 0,
      );
    } catch (e) {
      throw NetworkError(
          message: "Failed to add product: $e",
          userMessage: translateError(e),
          originalError: e,
        );
    }
  }

  Stream<List<Product>> getProducts({int limitAmt = 30}) {
    return _db
        .collection("products")
        .orderBy("createdAt", descending: true)
        .limit(limitAmt)
        .snapshots()
        .map((
      snapshot,
    ) {
      final products = snapshot.docs
          .map((doc) => Product.fromFirestore(doc))
          .where((p) => p.isActive)
          .toList();
      _sortByBoost(products);
      return products;
    });
  }

  Stream<List<Product>> getProductsByCategory(String category) {
    return _db
        .collection("products")
        .where("category", isEqualTo: category)
        .snapshots()
        .map((snapshot) {
          final products = snapshot.docs
              .map((doc) => Product.fromFirestore(doc))
              .where((p) => p.isActive)
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
        .snapshots()
        .map((snapshot) {
          final products = snapshot.docs
              .map((doc) => Product.fromFirestore(doc))
              .where((p) => p.isActive)
              .toList();
          _sortByBoost(products);
          return products;
        });
  }

  Stream<List<Product>> searchProducts(String query) {
    return _db.collection("products").snapshots().map((snapshot) {
      final products = snapshot.docs
          .map((doc) => Product.fromFirestore(doc))
          .where(
            (p) =>
                p.isActive &&
                (query.isEmpty ||
                    p.name.toLowerCase().contains(query.toLowerCase())),
          )
          .toList();
      _sortByBoost(products);
      return products;
    });
  }

  Stream<List<Product>> getProductsByBrand(String brand) {
    return _db
        .collection("products")
        .where("brand", isEqualTo: brand)
        .snapshots()
        .map((snapshot) {
          final products = snapshot.docs
              .map((doc) => Product.fromFirestore(doc))
              .where((p) => p.isActive)
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
              .where((p) => p.isActive)
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
  }) async {
    try {
      Map<String, dynamic> data = {};

      if (name != null) data["name"] = name;
      if (description != null) data["description"] = description;
      if (price != null) data["price"] = price;
      if (category != null) data["category"] = category;
      if (subcategory != null) data["subcategory"] = subcategory;
      if (stock != null) data["stock"] = stock;
      if (isWholesale != null) data["isWholesale"] = isWholesale;
      if (wholesaleTiers != null) data["wholesaleTiers"] = wholesaleTiers;
      if (variants != null) data["variants"] = variants;
      if (brand != null) data["brand"] = brand;
      if (condition != null) data["condition"] = condition;

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
      await _db.collection("products").doc(productId).delete();
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
        .snapshots()
        .map((snapshot) {
      final products = snapshot.docs
          .map((doc) => Product.fromFirestore(doc))
          .where((p) => p.isActive && p.isBoostedValid)
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
