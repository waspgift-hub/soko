import 'package:flutter/material.dart';

/// Reusable safe dropdown that prevents Flutter assertion
/// `There should be exactly one item with DropdownButton's value`.
class SafeDropdownFormField<T> extends StatelessWidget {
  const SafeDropdownFormField({
    super.key,
    required this.items,
    required this.onChanged,
    this.value,
    this.hint,
    this.labelText,
    this.decoration,
    this.validator,
    this.isExpanded = true,
    this.itemLabel,
    this.normalize,
  });

  final T? value;
  final List<T> items;
  final ValueChanged<T?> onChanged;
  final String? hint;
  final String? labelText;
  final InputDecoration? decoration;
  final String? Function(T?)? validator;
  final bool isExpanded;
  final String Function(T)? itemLabel;
  final String Function(T)? normalize;

  T? get _safeValue {
    if (value == null) return null;
    // normalize comparison for String types to avoid mismatch due to spaces/case
    final normValue = normalize != null ? normalize!(value as T) : value.toString().trim().toLowerCase();
    final exists = items.any((e) {
      final normItem = normalize != null ? normalize!(e) : e.toString().trim().toLowerCase();
      return normItem == normValue;
    });
    if (!exists) return null;
    // return original item that matches normalized value to keep correct object
    for (final e in items) {
      final normItem = normalize != null ? normalize!(e) : e.toString().trim().toLowerCase();
      if (normItem == normValue) return e;
    }
    return null;
  }

  List<T> get _dedupedItems {
    // Use normalized string to dedup while preserving first occurrence order
    final seen = <String>{};
    final result = <T>[];
    for (final item in items) {
      final key = normalize != null ? normalize!(item) : item.toString().trim().toLowerCase();
      if (seen.add(key)) result.add(item);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final safeItems = _dedupedItems;
    final safeValue = _safeValue;

    return DropdownButtonFormField<T>(
      isExpanded: isExpanded,
      initialValue: safeValue,
      decoration: decoration ??
          InputDecoration(
            labelText: labelText,
            hintText: hint,
            border: const OutlineInputBorder(),
            labelStyle: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
      hint: hint != null ? Text(hint!, overflow: TextOverflow.ellipsis) : null,
      items: safeItems
          .map((e) => DropdownMenuItem<T>(
                value: e,
                child: Text(itemLabel != null ? itemLabel!(e) : e.toString(), overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: onChanged,
      validator: validator,
    );
  }
}

/// Helper to normalize category strings safely
String normalizeCategory(String s) => s.trim().toLowerCase();
