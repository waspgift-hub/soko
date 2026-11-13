import os

root = r'C:\Users\user\Desktop\SOKO VIBE\ttr\soko_langu\lib\services'
filepath = os.path.join(root, 'product_service.dart')

with open(filepath, 'r', errors='ignore') as f:
    lines = f.readlines()

# Find the insertion point - after "})" that ends getProductsByCategoryAndSubcategory
# and before "  Stream<List<Product>> getProductsByBrand"
insert_line = None
for i, line in enumerate(lines):
    if '})' in line and i > 780 and i < 795:
        # Check if this is the right "}" by looking at surrounding context
        if i + 3 < len(lines) and 'getProductsByBrand' in lines[i + 3]:
            insert_line = i + 1  # Insert after this line
            break

if insert_line is None:
    print('ERROR: Could not find insertion point')
    exit(1)

# New methods to insert
new_methods = """  /// Firestore-paginated query using [categoryId] (Firestore doc ID = permanent UUID)
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

"""

# Insert the new methods
lines.insert(insert_line, new_methods)

with open(filepath, 'w', errors='ignore') as f:
    f.writelines(lines)

print('SUCCESS: Category ID methods inserted into product_service.dart')