import 'package:flutter/foundation.dart' hide Category;
import '../models/category_model.dart' as cat_model;
import '../services/category_service.dart';
import '../widgets/safe_dropdown.dart';

/// Provider for dynamic categories from Firebase/Firestore.
/// Handles normalization, deduplication and safe selection.
class CategoryProvider extends ChangeNotifier {
  final CategoryService _service = CategoryService();
  List<cat_model.Category> _categories = [];
  String? _selectedCategory;
  bool _loading = true;
  String? _error;

  List<cat_model.Category> get categories => _categories;
  // deduped names for dropdown
  List<String> get categoryNames => _categories.map((c) => c.name).toSet().toList()..sort((a, b) => normalizeCategory(a).compareTo(normalizeCategory(b)));
  String? get selectedCategory => _selectedCategory;
  bool get isLoading => _loading;
  String? get error => _error;

  CategoryProvider() {
    _listen();
  }

  void _listen() {
    _service.getCategories().listen(
      (cats) {
        // fallback to defaults if Firestore empty
        if (cats.isEmpty) {
          _categories = cat_model.getDefaultCategories().where((c) => c.isActive).toList();
        } else {
          _categories = cats;
        }
        _loading = false;
        _error = null;
        // validate selected value against new list
        if (_selectedCategory != null) {
          final exists = _categories.any((c) => normalizeCategory(c.name) == normalizeCategory(_selectedCategory!));
          if (!exists) _selectedCategory = null;
        }
        notifyListeners();
      },
      onError: (e) {
        _error = e.toString();
        _loading = false;
        notifyListeners();
      },
    );
  }

  void selectCategory(String? name) {
    if (name == null) {
      _selectedCategory = null;
    } else {
      // normalize and find actual canonical name
      final normalized = normalizeCategory(name);
      final match = _categories.firstWhere(
        (c) => normalizeCategory(c.name) == normalized,
        orElse: () => _categories.firstWhere((c) => c.name == name, orElse: () => _categories.first),
      );
      _selectedCategory = match.name;
    }
    notifyListeners();
  }

  // For subcategory example
  List<String> subcategoriesFor(String categoryName) {
    final cat = _categories.firstWhere(
      (c) => normalizeCategory(c.name) == normalizeCategory(categoryName),
      orElse: () => _categories.isNotEmpty ? _categories.first : cat_model.Category(id: '', name: '', nameSw: '', icon: '', subcategories: []),
    );
    return cat.subcategories.map((s) => s.name).toSet().toList();
  }
}
