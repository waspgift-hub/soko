import 'package:cloud_firestore/cloud_firestore.dart';

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
      icon: data['icon'] ?? '📦',
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

List<Category> getDefaultCategories() {
  return [
    // Electronics
    Category(
      id: 'electronics',
      name: 'Electronics',
      nameSw: 'Vifaa vya Umeme',
      icon: '📱',
      subcategories: [
        SubCategory(
          id: 'phones',
          name: 'Phones & Tablets',
          nameSw: 'Simu na Tableti',
        ),
        SubCategory(
          id: 'computers',
          name: 'Computers & Laptops',
          nameSw: 'Kompyuta na Laptops',
        ),
        SubCategory(id: 'tv_audio', name: 'TV & Audio', nameSw: 'TV na Sauti'),
        SubCategory(
          id: 'accessories',
          name: 'Accessories',
          nameSw: 'Vifaa vya Ziada',
        ),
      ],
      order: 1,
    ),
    // Fashion
    Category(
      id: 'fashion',
      name: 'Fashion',
      nameSw: 'Mavazi',
      icon: '👕',
      subcategories: [
        SubCategory(
          id: 'mens',
          name: "Men's Clothing",
          nameSw: 'Mavazi ya Wanaume',
        ),
        SubCategory(
          id: 'womens',
          name: "Women's Clothing",
          nameSw: 'Mavazi ya Wanawake',
        ),
        SubCategory(id: 'shoes', name: 'Shoes', nameSw: 'Viatu'),
        SubCategory(
          id: 'bags',
          name: 'Bags & Luggage',
          nameSw: 'Mikoba na Mashine',
        ),
        SubCategory(id: 'jewelry', name: 'Jewelry', nameSw: 'Vidhuru'),
      ],
      order: 2,
    ),
    // Home & Garden
    Category(
      id: 'home_garden',
      name: 'Home & Garden',
      nameSw: 'Nyumba na Bustani',
      icon: '🏠',
      subcategories: [
        SubCategory(id: 'furniture', name: 'Furniture', nameSw: 'Samani'),
        SubCategory(id: 'kitchen', name: 'Kitchen & Dining', nameSw: 'Jikoni'),
        SubCategory(
          id: 'decor',
          name: 'Home Decor',
          nameSw: 'Mapambo ya Nyumba',
        ),
        SubCategory(id: 'garden', name: 'Garden & Outdoor', nameSw: 'Bustani'),
        SubCategory(
          id: 'tools',
          name: 'DIY Tools',
          nameSw: 'Zana za Kushonaji',
        ),
      ],
      order: 3,
    ),
    // Automotive
    Category(
      id: 'automotive',
      name: 'Automotive',
      nameSw: 'Magari',
      icon: '🚗',
      subcategories: [
        SubCategory(
          id: 'car_parts',
          name: 'Car Parts',
          nameSw: 'Viwango vya Gari',
        ),
        SubCategory(
          id: 'accessories',
          name: 'Car Accessories',
          nameSw: 'Vifaa vya Gari',
        ),
        SubCategory(
          id: 'tools',
          name: 'Tools & Equipment',
          nameSw: 'Zana na Vifaa',
        ),
        SubCategory(id: 'motorcycles', name: 'Motorcycles', nameSw: 'Pikipiki'),
      ],
      order: 4,
    ),
    // Health & Beauty
    Category(
      id: 'health',
      name: 'Health & Beauty',
      nameSw: 'Afya na Urembo',
      icon: '💄',
      subcategories: [
        SubCategory(
          id: 'skincare',
          name: 'Skincare',
          nameSw: 'Utunzaji wa Ngozi',
        ),
        SubCategory(
          id: 'hair',
          name: 'Hair Care',
          nameSw: 'Utunzaji wa Nywele',
        ),
        SubCategory(id: 'makeup', name: 'Makeup', nameSw: 'Vipodozi'),
        SubCategory(
          id: 'supplements',
          name: 'Supplements',
          nameSw: 'Vidonge vya Afya',
        ),
      ],
      order: 5,
    ),
    // Sports & Entertainment
    Category(
      id: 'sports',
      name: 'Sports & Entertainment',
      nameSw: 'Michezo na Burudani',
      icon: '⚽',
      subcategories: [
        SubCategory(id: 'fitness', name: 'Fitness', nameSw: 'Mazoezi'),
        SubCategory(
          id: 'outdoor',
          name: 'Outdoor Sports',
          nameSw: 'Michezo ya Nje',
        ),
        SubCategory(
          id: 'games',
          name: 'Games & Toys',
          nameSw: 'Michesho na Vifaa',
        ),
        SubCategory(
          id: 'books',
          name: 'Books & Media',
          nameSw: 'Vitabu na Vyombo',
        ),
      ],
      order: 6,
    ),
    // Business & Industrial
    Category(
      id: 'business',
      name: 'Business & Industrial',
      nameSw: 'Biashara na Viwanda',
      icon: '🏭',
      subcategories: [
        SubCategory(id: 'machinery', name: 'Machinery', nameSw: 'Mashine'),
        SubCategory(id: 'construction', name: 'Construction', nameSw: 'Ujenzi'),
        SubCategory(id: 'agriculture', name: 'Agriculture', nameSw: 'Kilimo'),
        SubCategory(
          id: 'office',
          name: 'Office Supplies',
          nameSw: 'Vifaa vya Ofisi',
        ),
      ],
      order: 7,
    ),
    // Food & Beverages
    Category(
      id: 'food',
      name: 'Food & Beverages',
      nameSw: 'Chakula na Vinywaji',
      icon: '🍔',
      subcategories: [
        SubCategory(
          id: 'groceries',
          name: 'Groceries',
          nameSw: 'Mboga na Matunda',
        ),
        SubCategory(id: 'snacks', name: 'Snacks & Sweets', nameSw: 'Vitafunio'),
        SubCategory(id: 'beverages', name: 'Beverages', nameSw: 'Vinywaji'),
        SubCategory(id: 'spices', name: 'Spices & Herbs', nameSw: 'Viungo'),
      ],
      order: 8,
    ),
    // Maternal & Kids
    Category(
      id: 'maternal',
      name: 'Maternal & Kids',
      nameSw: 'Mama na Watoto',
      icon: '👶',
      subcategories: [
        SubCategory(
          id: 'baby_care',
          name: 'Baby Care',
          nameSw: 'Utunzaji wa Mtoto',
        ),
        SubCategory(
          id: 'kids_fashion',
          name: 'Kids Fashion',
          nameSw: 'Mavazi ya Watoto',
        ),
        SubCategory(
          id: 'toys',
          name: 'Kids Toys',
          nameSw: 'Michesho ya Watoto',
        ),
      ],
      order: 9,
    ),
    // Services
    Category(
      id: 'services',
      name: 'Services',
      nameSw: 'Huduma',
      icon: '🔧',
      subcategories: [
        SubCategory(
          id: 'home_services',
          name: 'Home Services',
          nameSw: 'Huduma za Nyumbani',
        ),
        SubCategory(
          id: 'repair',
          name: 'Repair & Maintenance',
          nameSw: 'Ukarabati',
        ),
        SubCategory(
          id: 'education',
          name: 'Education & Training',
          nameSw: 'Elimu',
        ),
      ],
      order: 10,
    ),
  ];
}
