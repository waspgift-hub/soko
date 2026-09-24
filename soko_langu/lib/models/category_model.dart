import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/marketplace_taxonomy.dart';
import '../utils/category_icons.dart';

/// Bundled category artwork. Drop a photo at the matching path to replace
/// the icon fallback; missing files fall back to icons automatically.
class CategoryArtwork {
  static const _dir = 'assets/images/categories';
  static const electronics = '$_dir/electronics.jpg';
  static const computers = '$_dir/computers.jpg';
  static const phones = '$_dir/phones.jpg';
  static const fashion = '$_dir/fashion.jpg';
  static const shoesBags = '$_dir/shoes_bags.jpg';
  static const health = '$_dir/health.jpg';
  static const homeGarden = '$_dir/home_garden.jpg';
  static const kitchen = '$_dir/kitchen.jpg';
  static const automotive = '$_dir/automotive.jpg';
  static const building = '$_dir/building.jpg';
  static const agriculture = '$_dir/agriculture.jpg';
  static const food = '$_dir/food.jpg';
  static const maternal = '$_dir/maternal.jpg';
  static const sports = '$_dir/sports.jpg';
  static const books = '$_dir/books.jpg';
  static const jewelry = '$_dir/jewelry.jpg';
  static const solar = '$_dir/solar.jpg';
  static const hobbies = '$_dir/hobbies.jpg';
  static const pets = '$_dir/pets.jpg';
  static const services = '$_dir/services.jpg';
}

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

  /// Artwork for this category: explicit [image] first, then a remote
  /// URL carried in [icon] by the v1 API.
  String? get displayImage {
    if (image != null && image!.isNotEmpty) return image;
    if (icon.startsWith('http')) return icon;
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
