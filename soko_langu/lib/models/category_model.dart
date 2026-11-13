import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/marketplace_taxonomy.dart';
import '../utils/category_icons.dart';

class Category {
  final String id;
  final String name;
  final String nameSw;
  final String icon;
  final String? image;
  final List<SubCategory> subcategories;
  final bool isActive;
  final int order;

  Category({
    required this.id,
    required this.name,
    required this.nameSw,
    required this.icon,
    this.image,
    required this.subcategories,
    this.isActive = true,
    this.order = 0,
  });

  /// Remote artwork URL for this category, or null when there is none.
  ///
  /// Only an `http(s)`/`//` value qualifies. The legacy `icon` column has
  /// carried both CDN URLs and Flutter bundle paths, and a bundle path is not
  /// artwork — accepting one here made every category tile attempt a load of
  /// a file that no longer exists and fall through to the icon, which is what
  /// kept the installed artwork pack invisible. Category photographs are
  /// resolved by taxonomy id through `CategoryArtworkService` instead.
  String? get displayImage {
    final v = image?.trim() ?? '';
    if (v.isNotEmpty && (v.startsWith('http') || v.startsWith('//'))) return v;
    final i = icon.trim();
    if (i.startsWith('http') || i.startsWith('//')) return i;
    return null;
  }

  factory Category.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    List<SubCategory> subs = [];
    if (data['subcategories'] != null) {
      for (var s in (data['subcategories'] as List)) {
        if (s is Map<String, dynamic>) {
          subs.add(SubCategory.fromMap(s));
        }
      }
    }

    return Category(
      id: doc.id,
      name: data['name'] ?? '',
      nameSw: data['nameSw'] ?? '',
      icon: data['icon'] ?? CategoryIconNames.package,
      image: data['image'],
      subcategories: subs,
      isActive: data['isActive'] ?? true,
      order: data['order'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'nameSw': nameSw,
    'icon': icon,
    'image': image,
    'subcategories': subcategories.map((s) => s.toMap()).toList(),
    'isActive': isActive,
    'order': order,
  };
}

class SubCategory {
  final String id;
  final String name;
  final String nameSw;
  final String? image;

  SubCategory({
    required this.id,
    required this.name,
    required this.nameSw,
    this.image,
  });

  factory SubCategory.fromMap(Map<String, dynamic> map) {
    return SubCategory(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      nameSw: map['nameSw'] ?? '',
      image: map['image'],
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'nameSw': nameSw,
    'image': image,
  };
}

/// Default categories built from the single taxonomy source, plus a
/// hidden legacy catch-all so old products still resolve.
/// Maps one taxonomy entry to its Firestore-shaped [Category].
Category categoryFromTaxonomy(TaxonomyCategory t) {
  return Category(
    id: t.id,
    name: t.name,
    nameSw: t.nameSw,
    icon: t.icon,
    image: t.image,
    subcategories: [
      for (final s in t.subs)
        SubCategory(id: s.id, name: s.name, nameSw: s.nameSw),
    ],
    order: t.order,
  );
}

List<Category> getDefaultCategories() {
  final cats = [
    for (final t in kMarketplaceTaxonomy) categoryFromTaxonomy(t),
    Category(
      id: 'others',
      name: 'Others',
      nameSw: 'Nyingine',
      icon: CategoryIconNames.package,
      subcategories: [
        SubCategory(id: 'other', name: 'Other', nameSw: 'Nyingine'),
        SubCategory(
          id: 'miscellaneous',
          name: 'Miscellaneous',
          nameSw: 'Mchanganyiko',
        ),
        SubCategory(
          id: 'uncategorized',
          name: 'Uncategorized',
          nameSw: 'Haina Kategoria',
        ),
      ],
      isActive: false,
      order: 999,
    ),
  ];
  return cats;
}
