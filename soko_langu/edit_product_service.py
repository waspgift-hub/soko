import os

root = r'C:\Users\user\Desktop\SOKO VIBE\ttr\soko_langu\lib\services'
filepath = os.path.join(root, 'product_service.dart')

with open(filepath, 'r', errors='ignore') as f:
    content = f.read()

# Find and replace - insert new methods before getProductsByBrand
old_target = """  }))

  Stream<List<Product>> getProductsByBrand(String brand) {"""

new_target = """})
    } return firestore.map((products) {
      _sortByBoosted(products);
      return products;
    });
  }

  /// Firestore-paginated query using [categoryId] (Firestore doc ID = permanent UUID)
  /// as the canonical identifier. Survives category-name changes.
  Future<(List<Product>, DocumentSnapshot<Map<String, dynamic>>?)> fetchProductsByCategoryId(
    String categoryId, {
    String? subcategory,
    int limit = 30,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    var query = _db
        .collection("products")
        .where('categoryId', isEqualTo: categoryId)
        .where('isActive', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(limit);
    if (subcategory != null) {
      query = query.where('subcategory', isEqualTo: subcategory);
    }
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

  /// Firestore-paginated query using [categoryId] + optional subcategory,
  /// with alias support for legacy category names.
  Stream<List<Product>> getProductsByCategoryAndSubcategoryId(
    String categoryId, {
    String? subcategory,
    Set<String>? categoryAliases,
    Set<String>? subcategoryAliases,
  }) {
    // Resolve category name from ID for alias matching (legacy support)
    final categories = <String>{categoryId, ...?categoryAliases}.toList();
    final subcategories =
        <String>{subcategory, ...?subcategoryAliases}.toList();
    final firestore = _db
        .collection("products")
        .where('categoryId', whereIn: categories)
        .where('subcategory', whereIn: subcategories)
        .where('isActive', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => Product.fromFirestore(doc))
          .toList();
    });
    return firestore.map((products) {
      _sortByBoosted(products);
      return products;
    });
  }

  Stream<List<Product>> getProductsByBrand(String brand) {"""

if old_target in content:
    new_content = content.replace(old_target, new_target)
    with open(filepath, 'w', errors='ignore') as f:
        f.write(new_content)
    print('Replacement successful')
else:
    print('old_target not found')
    # Debug: find the actual pattern
    idx = content.find('getProductsByBrand')
    if idx >= 0:
        print(f'Found getProductsByBrand at {idx}')
        print(repr(content[idx-100:idx+100]))