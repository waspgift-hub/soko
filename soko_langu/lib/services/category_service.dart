import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/category_model.dart';

class CategoryService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // =========================
  // 📡 GET ALL CATEGORIES
  // =========================
  Stream<List<Category>> getCategories() {
    return _db
        .collection("categories")
        .snapshots()
        .map((snapshot) {
          final cats = snapshot.docs
              .map((doc) => Category.fromFirestore(doc))
              .toList();
          cats.sort((a, b) => a.order.compareTo(b.order));
          return cats.where((c) => c.isActive).toList();
        });
  }

  // =========================
  // 📦 GET CATEGORY BY ID
  // =========================
  Future<Category?> getCategoryById(String categoryId) async {
    try {
      final doc = await _db.collection("categories").doc(categoryId).get();
      if (doc.exists) {
        return Category.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      throw Exception("Failed to get category: $e");
    }
  }

  // =========================
  // ➕ ADD DEFAULT CATEGORIES (Run once)
  // =========================
  Future<void> addDefaultCategories() async {
    try {
      final categories = getDefaultCategories();
      final batch = _db.batch();

      for (var category in categories) {
        final docRef = _db.collection("categories").doc(category.id);
        batch.set(docRef, category.toMap());
      }

      await batch.commit();
    } catch (e) {
      throw Exception("Failed to add default categories: $e");
    }
  }

  // =========================
  // ✏️ UPDATE CATEGORY
  // =========================
  Future<void> updateCategory(
    String categoryId,
    Map<String, dynamic> data,
  ) async {
    try {
      await _db.collection("categories").doc(categoryId).update(data);
    } catch (e) {
      throw Exception("Failed to update category: $e");
    }
  }
}
