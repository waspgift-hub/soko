/// MASTER CATEGORY TAXONOMY — canonical seed source (stable slugs).
///
/// Single source of truth for the global marketplace category hierarchy.
/// True for both the Flutter app defaults and the server seed script.
/// Ids are stable slugs so existing products/links do not break across
/// re-seeds.
library;

class MasterSubCategory {
  const MasterSubCategory(this.id, this.name, {this.nameSw});
  final String id;
  final String name;
  final String? nameSw;
}

class MasterCategory {
  const MasterCategory(
    this.id,
    this.name,
    this.icon,
    this.subcategories, {
    this.order,
  });
  final String id;
  final String name;
  final String icon;
  final List<MasterSubCategory> subcategories;
  final int? order;
}

/// Canonical top-level categories (global marketplace master, subset).
const List<MasterCategory> kMasterCategories = [
  // Electronics
  MasterCategory('electronics', 'Electronics', 'smartphone', [
    MasterSubCategory('phones', 'Phones & Tablets', nameSw: 'Simu na Tableti'),
    MasterSubCategory(
      'computers',
      'Computers & Laptops',
      nameSw: 'Kompyuta na Laptops',
    ),
    MasterSubCategory('tv_audio', 'TV & Audio', nameSw: 'TV na Sauti'),
    MasterSubCategory('accessories', 'Accessories', nameSw: 'Vifaa vya Ziada'),
  ], order: 1),
  // Fashion
  MasterCategory('fashion', 'Fashion', 'checkroom', [
    MasterSubCategory('mens', "Men's Clothing", nameSw: 'Mavazi ya Wanaume'),
    MasterSubCategory(
      'womens',
      "Women's Clothing",
      nameSw: 'Mavazi ya Wanawake',
    ),
    MasterSubCategory('shoes', 'Shoes', nameSw: 'Viatu'),
    MasterSubCategory('bags', 'Bags & Luggage', nameSw: 'Mikoba'),
    MasterSubCategory('jewelry', 'Jewelry', nameSw: 'Vidhuru'),
  ], order: 2),
  // Home & Garden
  MasterCategory('home_garden', 'Home & Garden', 'chair', [
    MasterSubCategory('furniture', 'Furniture', nameSw: 'Samani'),
    MasterSubCategory('kitchen', 'Kitchen & Dining', nameSw: 'Jikoni'),
    MasterSubCategory('decor', 'Decor', nameSw: 'Mapambo'),
    MasterSubCategory('garden', 'Garden & Outdoor', nameSw: 'Bustani'),
  ], order: 3),
  // Baby, Kids & Maternity
  MasterCategory('kids', 'Kids, Baby & Maternity', 'child_care', [
    MasterSubCategory(
      'baby_clothing',
      'Baby Clothing',
      nameSw: 'Mavazi ya Watoto',
    ),
    MasterSubCategory(
      'kids_clothing',
      'Kids Clothing',
      nameSw: 'Mavazi ya Watoto',
    ),
    MasterSubCategory('toys', 'Toys', nameSw: 'Michesho'),
    MasterSubCategory('nursery', 'Nursery', nameSw: 'Daws za Watoto'),
  ], order: 4),
  // Beauty & Health
  MasterCategory('health_beauty', 'Beauty & Health', 'spa', [
    MasterSubCategory('skincare', 'Skincare', nameSw: 'Utunzaji wa Ngozi'),
    MasterSubCategory('makeup', 'Makeup', nameSw: 'Mapambo ya Uso'),
    MasterSubCategory('hair', 'Hair Care', nameSw: 'Utunzaji wa Nywele'),
    MasterSubCategory('fragrance', 'Fragrance', nameSw: 'Manukato'),
  ], order: 5),
  // Automotive
  MasterCategory('automotive', 'Automotive', 'car', [
    MasterSubCategory('cars', 'Cars', nameSw: 'Magari'),
    MasterSubCategory('car_parts', 'Car Parts', nameSw: 'Vipuri vya Gari'),
    MasterSubCategory('motorcycles', 'Motorcycles', nameSw: 'Pikipiki'),
    MasterSubCategory(
      'accessories',
      'Car Accessories',
      nameSw: 'Vifaa vya Gari',
    ),
  ], order: 6),
];
