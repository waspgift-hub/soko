import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/category_provider.dart';
import '../safe_dropdown.dart';

/// Example 1: Basic SafeDropdown with static list (Prompt 2)
class StaticCategoryDropdownExample extends StatefulWidget {
  const StaticCategoryDropdownExample({super.key});
  @override
  State<StaticCategoryDropdownExample> createState() => _StaticCategoryDropdownExampleState();
}

class _StaticCategoryDropdownExampleState extends State<StaticCategoryDropdownExample> {
  String? _selected = 'Electronics';
  // intentionally duplicated to show deduplication
  final _rawCategories = ['Electronics', 'Fashion', 'Electronics ', ' fashion', 'Home'];

  @override
  Widget build(BuildContext context) {
    return SafeDropdownFormField<String>(
      value: _selected,
      items: _rawCategories,
      labelText: 'Category',
      hint: 'Select category',
      // normalize handles trim + lowercase to match "Electronics" vs " electronics "
      normalize: normalizeCategory,
      itemLabel: (c) => c,
      validator: (v) => v == null ? 'Select a category' : null,
      onChanged: (v) => setState(() => _selected = v),
    );
  }
}

/// Example 2: Dynamic Firebase categories with Provider (Prompt 3 + State Management)
class ProviderCategoryDropdown extends StatelessWidget {
  const ProviderCategoryDropdown({super.key});
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => CategoryProvider(),
      child: Consumer<CategoryProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) return const CircularProgressIndicator();
          if (provider.error != null) return Text('Error: ${provider.error}');
          return SafeDropdownFormField<String>(
            value: provider.selectedCategory,
            items: provider.categoryNames,
            labelText: 'Category',
            hint: 'Select category',
            normalize: normalizeCategory,
            validator: (v) => v == null ? 'Required' : null,
            onChanged: provider.selectCategory,
          );
        },
      ),
    );
  }
}

/// Example 3: Direct Firestore Stream without Provider (Prompt 3 - StatefulWidget)
/// Shows normalization (trim, lowercase) to prevent matching errors.
class FirestoreCategoryDropdown extends StatefulWidget {
  const FirestoreCategoryDropdown({super.key});
  @override
  State<FirestoreCategoryDropdown> createState() => _FirestoreCategoryDropdownState();
}

class _FirestoreCategoryDropdownState extends State<FirestoreCategoryDropdown> {
  String? _selected = 'Electronics';
  List<String> _categories = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchCategories();
  }

  Future<void> _fetchCategories() async {
    // Simulate API/Firebase fetch
    await Future.delayed(const Duration(milliseconds: 500));
    final fetched = ['Electronics', 'Fashion', 'Home & Garden', 'Electronics']; // duplicate intentionally
    if (!mounted) return;
    setState(() {
      // normalize and dedup before state update
      _categories = fetched.map((e) => e.trim()).toSet().toList();
      _loading = false;
      // validate selected value still exists after fetch
      final normalizedSelected = _selected?.trim().toLowerCase();
      final exists = _categories.any((c) => c.trim().toLowerCase() == normalizedSelected);
      if (!exists) _selected = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const CircularProgressIndicator();
    return SafeDropdownFormField<String>(
      value: _selected,
      items: _categories,
      labelText: 'Category',
      hint: 'Select category',
      normalize: (s) => s.trim().toLowerCase(),
      onChanged: (v) => setState(() => _selected = v),
    );
  }
}
