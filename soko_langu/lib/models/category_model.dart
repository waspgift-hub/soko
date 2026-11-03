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
      icon: data['icon'] ?? 'other',
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
  SubCategory s(String id, String en, String sw) =>
      SubCategory(id: id, name: en, nameSw: sw);

  return [
    Category(
      id: 'electronics',
      name: 'Electronics',
      nameSw: 'Vifaa vya Elektroniki',
      icon: 'electronics',
      subcategories: [
        s('televisions', 'TVs', 'TV'),
        s('audio', 'Audio & Speakers', 'Sauti na Spika'),
        s('cameras', 'Cameras', 'Kamera'),
        s('accessories', 'Electronics Accessories', 'Vifaa vya Elektroniki'),
      ],
      order: 1,
    ),
    Category(
      id: 'phones_tablets',
      name: 'Phones & Tablets',
      nameSw: 'Simu na Tableti',
      icon: 'phones_tablets',
      subcategories: [
        s('smartphones', 'Smartphones', 'Simu janja'),
        s('feature_phones', 'Feature Phones', 'Simu za kawaida'),
        s('tablets', 'Tablets', 'Tableti'),
        s('phone_accessories', 'Cases, Chargers & Accessories', 'Vifuniko, Chaja na Vifaa'),
      ],
      order: 2,
    ),
    Category(
      id: 'fashion',
      name: 'Fashion',
      nameSw: 'Mavazi',
      icon: 'fashion',
      subcategories: [
        s('mens_clothing', "Men's Clothing", 'Mavazi ya Wanaume'),
        s('womens_clothing', "Women's Clothing", 'Mavazi ya Wanawake'),
        s('shoes', 'Shoes', 'Viatu'),
        s('bags', 'Bags & Luggage', 'Mikoba na Mizigo'),
        s('jewelry', 'Jewelry & Watches', 'Mapambo na Saa'),
      ],
      order: 3,
    ),
    Category(
      id: 'home_living',
      name: 'Home & Living',
      nameSw: 'Nyumba na Maisha',
      icon: 'home_living',
      subcategories: [
        s('furniture', 'Furniture', 'Samani'),
        s('kitchen', 'Kitchen & Dining', 'Jikoni na Chakula'),
        s('bedding', 'Bedding & Textiles', 'Mashuka na Nguo za Nyumbani'),
        s('decor', 'Home Decor', 'Mapambo ya Nyumba'),
        s('lighting', 'Lighting', 'Taa na Mwangaza'),
      ],
      order: 4,
    ),
    Category(
      id: 'beauty_personal_care',
      name: 'Beauty & Personal Care',
      nameSw: 'Urembo na Matunzo Binafsi',
      icon: 'beauty',
      subcategories: [
        s('skincare', 'Skin Care', 'Utunzaji wa Ngozi'),
        s('haircare', 'Hair Care', 'Utunzaji wa Nywele'),
        s('fragrance', 'Fragrance', 'Manukato'),
        s('beauty_tools', 'Beauty Tools & Accessories', 'Vifaa vya Urembo'),
      ],
      order: 5,
    ),
    Category(
      id: 'vehicles_parts',
      name: 'Vehicles & Parts',
      nameSw: 'Magari na Vipuri',
      icon: 'vehicles',
      subcategories: [
        s('cars', 'Cars', 'Magari'),
        s('motorcycles', 'Motorcycles', 'Pikipiki'),
        s('car_parts', 'Car Parts', 'Vipuri vya Magari'),
        s('vehicle_accessories', 'Vehicle Accessories', 'Vifaa vya Magari'),
      ],
      order: 6,
    ),
    Category(
      id: 'agriculture',
      name: 'Agriculture',
      nameSw: 'Kilimo',
      icon: 'agriculture',
      subcategories: [
        s('farm_tools', 'Farm Tools', 'Zana za Kilimo'),
        s('irrigation', 'Irrigation Equipment', 'Vifaa vya Umwagiliaji'),
        s('storage', 'Storage & Processing Equipment', 'Vifaa vya Kuhifadhi na Kusindika'),
        s('livestock_equipment', 'Livestock Equipment', 'Vifaa vya Mifugo'),
      ],
      order: 7,
    ),
    Category(
      id: 'food_groceries',
      name: 'Food & Groceries',
      nameSw: 'Chakula na Mahitaji ya Nyumbani',
      icon: 'food',
      subcategories: [
        s('groceries', 'Groceries', 'Mahitaji ya Nyumbani'),
        s('packaged_food', 'Packaged Food', 'Vyakula Vilivyofungashwa'),
        s('fresh_food', 'Fresh Food', 'Vyakula Vibichi'),
        s('beverages', 'Beverages', 'Vinywaji'),
      ],
      order: 8,
    ),
    Category(
      id: 'sports_outdoors',
      name: 'Sports & Outdoors',
      nameSw: 'Michezo na Vifaa vya Nje',
      icon: 'sports',
      subcategories: [
        s('fitness', 'Fitness Equipment', 'Vifaa vya Mazoezi'),
        s('sports_gear', 'Sports Gear', 'Vifaa vya Michezo'),
        s('outdoor', 'Outdoor Equipment', 'Vifaa vya Nje'),
        s('games_toys', 'Games & Toys', 'Michezo na Vichezeo'),
      ],
      order: 9,
    ),
    Category(
      id: 'baby_kids',
      name: 'Baby & Kids',
      nameSw: 'Watoto na Mahitaji yao',
      icon: 'baby',
      subcategories: [
        s('baby_care', 'Baby Care', 'Matunzo ya Mtoto'),
        s('kids_fashion', 'Kids Fashion', 'Mavazi ya Watoto'),
        s('toys', 'Toys', 'Vichezeo'),
        s('kids_gear', 'Kids Gear', 'Vifaa vya Watoto'),
      ],
      order: 10,
    ),
    Category(
      id: 'business_office',
      name: 'Business & Office',
      nameSw: 'Biashara na Ofisi',
      icon: 'business',
      subcategories: [
        s('office_supplies', 'Office Supplies', 'Vifaa vya Ofisi'),
        s('commercial_equipment', 'Commercial Equipment', 'Vifaa vya Biashara'),
        s('packaging', 'Packaging Supplies', 'Vifaa vya Ufungashaji'),
        s('shop_fixtures', 'Shop Fixtures', 'Vifaa vya Maduka'),
      ],
      order: 11,
    ),
    Category(
      id: 'hardware_tools',
      name: 'Hardware & Tools',
      nameSw: 'Vifaa na Zana',
      icon: 'tools',
      subcategories: [
        s('hand_tools', 'Hand Tools', 'Zana za Mkono'),
        s('power_tools', 'Power Tools', 'Zana za Umeme'),
        s('building_materials', 'Building Materials', 'Vifaa vya Ujenzi'),
        s('plumbing', 'Plumbing & Hardware', 'Mabomba na Vifaa vya Ufundi'),
      ],
      order: 12,
    ),
    Category(
      id: 'other_physical',
      name: 'Other Products',
      nameSw: 'Bidhaa Nyingine',
      icon: 'other',
      subcategories: [
        s('collectibles', 'Collectibles', 'Vitu vya Kukusanya'),
        s('gifts', 'Gifts', 'Zawadi'),
        s('miscellaneous', 'Miscellaneous', 'Mchanganyiko'),
      ],
      order: 13,
    ),
  ];
}

/// Converts stored legacy emoji glyphs or modern semantic icon keys into
/// stable Material icons. Emojis are never rendered by the UI.
IconData categoryIconFor(String glyph) {
  switch (glyph.trim().toLowerCase()) {
    case 'electronics':
    case '📱':
      return Icons.devices_other_rounded;
    case 'phones_tablets':
      return Icons.phone_android_rounded;
    case 'fashion':
    case '👕':
    case '👗':
      return Icons.checkroom_rounded;
    case 'home_living':
    case '🏠':
    case '🛋️':
    case '🪑':
      return Icons.home_work_outlined;
    case 'beauty':
    case '💄':
      return Icons.auto_awesome_outlined;
    case 'vehicles':
    case '🚗':
      return Icons.directions_car_filled_outlined;
    case 'agriculture':
    case '🌾':
      return Icons.agriculture_outlined;
    case 'food':
    case '🍎':
    case '🍔':
    case '🥦':
      return Icons.shopping_basket_outlined;
    case 'sports':
    case '⚽':
    case '🏀':
      return Icons.sports_soccer_outlined;
    case 'baby':
    case '👶':
      return Icons.child_friendly_outlined;
    case 'business':
    case '🏭':
      return Icons.business_center_outlined;
    case 'tools':
    case '🔧':
      return Icons.handyman_outlined;
    case 'other':
    case 'other_physical':
    case '📦':
      return Icons.category_outlined;
    default:
      return Icons.category_outlined;
  }
}
