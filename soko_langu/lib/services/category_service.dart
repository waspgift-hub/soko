import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../models/category_model.dart';
import 'api_config.dart';

class CategoryService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  List<Category>? _cached;
  Stream<List<Category>>? _cachedStream;

  // =========================
  // 📡 GET ALL CATEGORIES
  // =========================
  Stream<List<Category>> getCategories() {
    if (_cachedStream != null) return _cachedStream!;
    _cachedStream = _db.collection("categories").snapshots().map((snapshot) {
      if (snapshot.docs.isEmpty) {
        return getDefaultCategories();
      }
      final cats = snapshot.docs
          .map((doc) => Category.fromFirestore(doc))
          .toList();
      cats.sort((a, b) => a.order.compareTo(b.order));
      _cached = cats.where((c) => c.isActive).toList();
      return _cached!;
    });
    return _cachedStream!;
  }

  List<Category> get cached => _cached ?? [];

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

  Future<void> addDefaultCategories() async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not logged in');
      final token = await user.getIdToken(true);
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/categories/add-defaults'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      final result = jsonDecode(resp.body);
      if (result['success'] != true) {
        throw Exception(result['error'] ?? 'Failed to add default categories');
      }
    } catch (e) {
      throw Exception("Failed to add default categories: $e");
    }
  }

  Future<void> updateCategory(
    String categoryId,
    Map<String, dynamic> data,
  ) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not logged in');
      final token = await user.getIdToken(true);
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/categories/update'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({ 'categoryId': categoryId, 'data': data }),
      );
      final result = jsonDecode(resp.body);
      if (result['success'] != true) {
        throw Exception(result['error'] ?? 'Failed to update category');
      }
    } catch (e) {
      throw Exception("Failed to update category: $e");
    }
  }
}
