import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/product_model.dart';
import 'cloudinary_service.dart';
import '../utils/network_error.dart';

int _tierOrder(String tier) {
  switch (tier) {
    case 'silver':
      return 0;
    case 'premium':
      return 1;
    default:
      return 2;
  }
}

bool _isTrendingValid(Product p) =>
    p.isBoosted && p.boostedUntil != null && DateTime.now().isBefore(p.boostedUntil!);

void _sortByTier(List<Product> products) {
  products.sort((a, b) {
    final aTrending = _isTrendingValid(a) ? 0 : 1;
    final bTrending = _isTrendingValid(b) ? 0 : 1;
    final trendingCmp = aTrending.compareTo(bTrending);
    if (trendingCmp != 0) return trendingCmp;

    final aFeatured = a.isFeaturedValid ? 0 : 1;
    final bFeatured = b.isFeaturedValid ? 0 : 1;
    final f = aFeatured.compareTo(bFeatured);
    if (f != 0) return f;
    final t = _tierOrder(a.sellerTier).compareTo(_tierOrder(b.sellerTier));
    if (t != 0) return t;
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
    String location = 'Tanzania',
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

      String sellerTier = 'free';
      final userDoc = await _db.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        sellerTier = userDoc.data()?['accountTier'] as String? ?? 'free';
      }

      await _db.collection("products").add({
        "name": name,
        "description": description,
        "price": price,
        "currency": currency,
        "images": imageUrls,
        "sellerId": user.uid,
        "sellerName": sellerName,
        "sellerTier": sellerTier,
        "category": category,
        "subcategory": subcategory,
        "location": location,
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
        "pendingReview": false,
        "createdAt": FieldValue.serverTimestamp(),
      });
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
        .where('isActive', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(limitAmt)
        .snapshots()
        .map((snapshot) {
      final products =
          snapshot.docs.map((doc) => Product.fromFirestore(doc)).toList();
      _sortByTier(products);
      return products;
    });
  }

  Stream<List<Product>> getProductsByCategory(String category) {
    return _db
        .collection("products")
        .where('isActive', isEqualTo: true)
        .where("category", isEqualTo: category)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      final products =
          snapshot.docs.map((doc) => Product.fromFirestore(doc)).toList();
      _sortByTier(products);
      return products;
    });
  }

  Stream<List<Product>> getProductsByCategoryAndSubcategory(
    String category,
    String subcategory,
  ) {
    return _db
        .collection("products")
        .where('isActive', isEqualTo: true)
        .where("category", isEqualTo: category)
        .where("subcategory", isEqualTo: subcategory)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      final products =
          snapshot.docs.map((doc) => Product.fromFirestore(doc)).toList();
      _sortByTier(products);
      return products;
    });
  }

  Stream<List<Product>> searchProducts(String query) {
    return _db
        .collection("products")
        .where('isActive', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      final products = snapshot.docs
          .map((doc) => Product.fromFirestore(doc))
          .where(
            (p) =>
                query.isEmpty ||
                p.name.toLowerCase().contains(query.toLowerCase()),
          )
          .toList();
      _sortByTier(products);
      return products;
    });
  }

  Stream<List<Product>> getProductsByBrand(String brand) {
    return _db
        .collection("products")
        .where('isActive', isEqualTo: true)
        .where("brand", isEqualTo: brand)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      final products =
          snapshot.docs.map((doc) => Product.fromFirestore(doc)).toList();
      _sortByTier(products);
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
      final ref = _db.collection("products").doc(productId);

      // 1. Delete all comments + replies
      final comments = await ref.collection("comments").get();
      for (final comment in comments.docs) {
        final replies = await comment.reference.collection("replies").get();
        if (replies.docs.isNotEmpty) {
          final batch = _db.batch();
          for (final reply in replies.docs) batch.delete(reply.reference);
          await batch.commit();
        }
        await comment.reference.delete();
      }

      // 2. End active flash sales for this product
      final flashSales = await _db
          .collection("flash_sales")
          .where("productId", isEqualTo: productId)
          .where("isActive", isEqualTo: true)
          .get();
      for (final sale in flashSales.docs) {
        await sale.reference.update({"status": "ended", "isActive": false});
      }

      // 3. Delete cart items referencing this product
      final cartItems = await _db
          .collectionGroup("items")
          .where(FieldPath.documentId, isEqualTo: productId)
          .get();
      if (cartItems.docs.isNotEmpty) {
        final batch = _db.batch();
        for (final item in cartItems.docs) batch.delete(item.reference);
        await batch.commit();
      }

      // 4. Delete the product document
      await ref.delete();
    } catch (e) {
      throw NetworkError(
          message: "Delete failed: $e",
          userMessage: translateError(e),
          originalError: e,
        );
    }
  }

  Future<void> toggleProductActive(String productId, bool active) async {
    try {
      await _db.collection("products").doc(productId).update({
        'isActive': active,
        'pendingReview': !active,
      });
    } catch (e) {
      throw NetworkError(
          message: "Toggle failed: $e",
          userMessage: translateError(e),
          originalError: e,
        );
    }
  }

  Future<void> boostProduct(String productId, Duration duration) async {
    try {
      final boostedUntil = DateTime.now().add(duration);
      await _db.collection("products").doc(productId).update({
        'isBoosted': true,
        'boostedUntil': Timestamp.fromDate(boostedUntil),
      });
    } catch (e) {
      throw NetworkError(
          message: "Boost failed: $e",
          userMessage: translateError(e),
          originalError: e,
        );
    }
  }

  Stream<List<Product>> getAllProductsForAdmin({int limitAmt = 50}) {
    return _db.collection("products").limit(limitAmt).snapshots().map((
      snapshot,
    ) {
      return snapshot.docs
          .map((doc) => Product.fromFirestore(doc))
          .toList();
    });
  }

  Stream<List<Product>> getBoostedProducts() {
    final now = DateTime.now();
    return _db
        .collection("products")
        .where("isBoosted", isEqualTo: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => Product.fromFirestore(doc))
          .where((p) => p.isActive && p.boostedUntil != null && now.isBefore(p.boostedUntil!))
          .toList();
    });
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

  Future<void> updateAllSellerProductsTier(String sellerId, String tier) async {
    try {
      final products = await _db
          .collection("products")
          .where("sellerId", isEqualTo: sellerId)
          .get();

      final batch = _db.batch();
      for (var doc in products.docs) {
        batch.update(doc.reference, {'sellerTier': tier});
      }
      await batch.commit();
    } catch (e) {
      throw NetworkError(
          message: "Failed to update products tier: $e",
          userMessage: translateError(e),
          originalError: e,
        );
    }
  }
}
