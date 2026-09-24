/// Single authoritative marketplace taxonomy.
///
/// Categories, subcategories, brands, and category-aware filters live here.
/// [getDefaultCategories] (category_model.dart) builds its Firestore-shaped
/// list from this file so screens never duplicate category definitions.
///
/// Product rule: physical products and in-person services only. Digital
/// goods (e-books, courses, downloads, licenses, online-only services)
/// must never be added to this taxonomy.

library;

/// Attribute/option filter section inside a category.
class TaxFilter {
  final String key;
  final String labelKey;
  final List<String> options;
  const TaxFilter({
    required this.key,
    required this.labelKey,
    this.options = const [],
  });
}

/// One subcategory: visual fallback is [icon], server art via image.
class TaxonomySub {
  final String id;
  final String name;
  final String nameSw;
  final String icon;
  final List<String> aliases;
  const TaxonomySub(
    this.id,
    this.name,
    this.icon, {
    this.nameSw = '',
    this.aliases = const [],
  });
}

/// Brand shown as a neutral initial-avatar + name (no copied logos).
class TaxonomyBrand {
  final String id;
  final String name;
  const TaxonomyBrand(this.id, this.name);
}

class TaxonomyCategory {
  final String id;
  final String name;
  final String nameSw;
  final String icon;
  final String image;
  final int order;
  final bool popular;
  final List<String> aliases;
  final List<TaxonomySub> subs;
  final List<TaxonomyBrand> brands;
  final List<TaxFilter> filters;
  final List<String> popularFilters;
  const TaxonomyCategory({
    required this.id,
    required this.name,
    this.nameSw = '',
    required this.icon,
    required this.image,
    required this.order,
    this.popular = false,
    this.aliases = const [],
    this.subs = const [],
    this.brands = const [],
    this.filters = const [],
    this.popularFilters = const [],
  });
}

const List<TaxonomyCategory> kMarketplaceTaxonomy = [
  TaxonomyCategory(
    id: 'electronics',
    name: 'Electronics & Technology',
    nameSw: 'Elektroniki na Teknolojia',
    icon: 'devices',
    image: 'assets/images/categories/electronics.jpg',
    order: 1,
    popular: true,
    aliases: ['Electronics'],
    subs: [
      TaxonomySub('tvs', 'TVs', 'tv', nameSw: 'TV', aliases: ['TV & Audio']),
      TaxonomySub('audio', 'Audio & Speakers', 'speaker', nameSw: 'Sauti na Spika'),
      TaxonomySub('cameras', 'Cameras & Drones', 'camera', nameSw: 'Kamera na Droni'),
      TaxonomySub('wearables', 'Wearables', 'watch', nameSw: 'Vivaa Janja'),
      TaxonomySub('gaming', 'Gaming Consoles', 'games', nameSw: 'Michezo ya Video'),
      TaxonomySub('networking', 'Networking', 'router', nameSw: 'Mitandao'),
      TaxonomySub('elec_accessories', 'Accessories', 'package', nameSw: 'Vifaa', aliases: ['Accessories']),
    ],
    brands: [
      TaxonomyBrand('samsung', 'Samsung'),
      TaxonomyBrand('sony', 'Sony'),
      TaxonomyBrand('lg', 'LG'),
      TaxonomyBrand('hisense', 'Hisense'),
      TaxonomyBrand('tcl', 'TCL'),
      TaxonomyBrand('philips', 'Philips'),
      TaxonomyBrand('jbl', 'JBL'),
      TaxonomyBrand('bose', 'Bose'),
      TaxonomyBrand('anker', 'Anker'),
      TaxonomyBrand('oraimo', 'Oraimo'),
    ],
    filters: [
      TaxFilter(key: 'screen', labelKey: 'screen_size', options: ['32"', '43"', '50"', '55"', '65"+']),
    ],
    popularFilters: ['topRated', 'verified'],
  ),
  TaxonomyCategory(
    id: 'computers',
    name: 'Computers & Office',
    nameSw: 'Kompyuta na Ofisi',
    icon: 'computer',
    image: 'assets/images/categories/computers.jpg',
    order: 2,
    popular: true,
    subs: [
      TaxonomySub('laptops', 'Laptops', 'laptop', nameSw: 'Laptop', aliases: ['Computers & Laptops']),
      TaxonomySub('desktops', 'Desktops', 'computer', nameSw: 'Desktop'),
      TaxonomySub('monitors', 'Monitors', 'monitor', nameSw: 'Monitor'),
      TaxonomySub('printers', 'Printers & Copiers', 'printer', nameSw: 'Printa'),
      TaxonomySub('storage', 'Storage & Memory', 'storage', nameSw: 'Hifadhi Data'),
      TaxonomySub('comp_accessories', 'Keyboards & Mice', 'keyboard', nameSw: 'Kibodi na Mausi'),
    ],
    brands: [
      TaxonomyBrand('hp', 'HP'),
      TaxonomyBrand('dell', 'Dell'),
      TaxonomyBrand('lenovo', 'Lenovo'),
      TaxonomyBrand('apple', 'Apple'),
      TaxonomyBrand('asus', 'ASUS'),
      TaxonomyBrand('acer', 'Acer'),
      TaxonomyBrand('msi', 'MSI'),
      TaxonomyBrand('canon', 'Canon'),
      TaxonomyBrand('epson', 'Epson'),
    ],
    filters: [
      TaxFilter(key: 'ram', labelKey: 'ram', options: ['4GB', '8GB', '16GB', '32GB']),
      TaxFilter(key: 'storage', labelKey: 'storage', options: ['128GB', '256GB', '512GB', '1TB']),
      TaxFilter(key: 'processor', labelKey: 'processor', options: ['Intel i3', 'Intel i5', 'Intel i7', 'AMD Ryzen', 'Apple M1', 'Apple M2', 'Apple M3']),
      TaxFilter(key: 'screen', labelKey: 'screen_size', options: ['11"', '13"', '14"', '15.6"', '17"']),
      TaxFilter(key: 'os', labelKey: 'os', options: ['Windows', 'macOS', 'Linux', 'ChromeOS']),
    ],
    popularFilters: ['topRated', 'verified'],
  ),
  TaxonomyCategory(
    id: 'phones',
    name: 'Phones & Accessories',
    nameSw: 'Simu na Vifaa',
    icon: 'smartphone',
    image: 'assets/images/categories/phones.jpg',
    order: 3,
    popular: true,
    subs: [
      TaxonomySub('smartphones', 'Smartphones', 'smartphone', nameSw: 'Simu Janja', aliases: ['Phones & Tablets', 'Phones']),
      TaxonomySub('feature_phones', 'Feature Phones', 'phone', nameSw: 'Simu za Kawaida'),
      TaxonomySub('cases', 'Cases & Covers', 'cases', nameSw: 'Kava za Simu'),
      TaxonomySub('chargers', 'Chargers & Cables', 'charger', nameSw: 'Chaja na Nyaya'),
      TaxonomySub('powerbanks', 'Power Banks', 'battery', nameSw: 'Power Bank'),
      TaxonomySub('earphones', 'Earphones & Earbuds', 'earphones', nameSw: 'Earphones'),
      TaxonomySub('smartwatches', 'Smart Watches', 'watch', nameSw: 'Saa Janja'),
    ],
    brands: [
      TaxonomyBrand('samsung', 'Samsung'),
      TaxonomyBrand('apple', 'Apple'),
      TaxonomyBrand('xiaomi', 'Xiaomi'),
      TaxonomyBrand('tecno', 'Tecno'),
      TaxonomyBrand('infinix', 'Infinix'),
      TaxonomyBrand('itel', 'Itel'),
      TaxonomyBrand('oppo', 'Oppo'),
      TaxonomyBrand('vivo', 'Vivo'),
      TaxonomyBrand('realme', 'Realme'),
      TaxonomyBrand('nokia', 'Nokia'),
      TaxonomyBrand('huawei', 'Huawei'),
      TaxonomyBrand('google', 'Google'),
      TaxonomyBrand('oraimo', 'Oraimo'),
      TaxonomyBrand('anker', 'Anker'),
    ],
    filters: [
      TaxFilter(key: 'storage', labelKey: 'storage', options: ['32GB', '64GB', '128GB', '256GB', '512GB']),
      TaxFilter(key: 'ram', labelKey: 'ram', options: ['2GB', '3GB', '4GB', '6GB', '8GB', '12GB']),
      TaxFilter(key: 'network', labelKey: 'network', options: ['4G', '5G']),
    ],
    popularFilters: ['fiveG', 'dualSim', 'amoled', 'bigBattery'],
  ),
  TaxonomyCategory(
    id: 'fashion',
    name: 'Fashion & Clothing',
    nameSw: 'Mavazi',
    icon: 'checkroom',
    image: 'assets/images/categories/fashion.jpg',
    order: 4,
    popular: true,
    aliases: ['Fashion'],
    subs: [
      TaxonomySub('menswear', 'Men\'s Clothing', 'checkroom', nameSw: 'Mavazi ya Wanaume', aliases: ['Men\'s Clothing']),
      TaxonomySub('womenswear', 'Women\'s Clothing', 'dress', nameSw: 'Mavazi ya Wanawake', aliases: ['Women\'s Clothing']),
      TaxonomySub('traditional', 'Traditional Wear', 'traditional', nameSw: 'Vitenge na Kanzu'),
      TaxonomySub('suits', 'Suits & Blazers', 'suits', nameSw: 'Suti'),
      TaxonomySub('tops', 'T-Shirts & Tops', 'tshirt', nameSw: 'Tisheti'),
      TaxonomySub('jeans', 'Jeans & Trousers', 'jeans', nameSw: 'Jeans na Suruali'),
      TaxonomySub('dresses', 'Dresses & Skirts', 'dress', nameSw: 'Magauni na Sketi'),
    ],
    brands: [
      TaxonomyBrand('nike', 'Nike'),
      TaxonomyBrand('adidas', 'Adidas'),
      TaxonomyBrand('puma', 'Puma'),
      TaxonomyBrand('reebok', 'Reebok'),
      TaxonomyBrand('newbalance', 'New Balance'),
      TaxonomyBrand('levis', 'Levi\'s'),
      TaxonomyBrand('zara', 'Zara'),
      TaxonomyBrand('handm', 'H&M'),
    ],
    filters: [
      TaxFilter(key: 'size', labelKey: 'size', options: ['XS', 'S', 'M', 'L', 'XL', 'XXL']),
      TaxFilter(key: 'gender', labelKey: 'gender', options: ['Men', 'Women', 'Unisex']),
      TaxFilter(key: 'color', labelKey: 'color', options: ['Black', 'White', 'Blue', 'Red', 'Green', 'Yellow', 'Brown', 'Grey', 'Multi']),
      TaxFilter(key: 'material', labelKey: 'material', options: ['Cotton', 'Polyester', 'Denim', 'Leather', 'Kitenge', 'Linen']),
    ],
    popularFilters: ['topRated', 'verified'],
  ),
  TaxonomyCategory(
    id: 'shoes_bags',
    name: 'Shoes & Bags',
    nameSw: 'Viatu na Mifuko',
    icon: 'shoes',
    image: 'assets/images/categories/shoes_bags.jpg',
    order: 5,
    subs: [
      TaxonomySub('sneakers', 'Sneakers', 'shoes', nameSw: 'Sneakers', aliases: ['Shoes']),
      TaxonomySub('mens_shoes', 'Men\'s Shoes', 'shoes', nameSw: 'Viatu vya Wanaume'),
      TaxonomySub('womens_shoes', 'Women\'s Shoes', 'heels', nameSw: 'Viatu vya Wanawake'),
      TaxonomySub('sandals', 'Sandals & Slippers', 'sandals', nameSw: 'Ndala'),
      TaxonomySub('handbags', 'Handbags', 'handbag', nameSw: 'Mikoba', aliases: ['Bags & Luggage']),
      TaxonomySub('backpacks', 'Backpacks', 'backpack', nameSw: 'Mabegi ya Mgongo'),
      TaxonomySub('luggage', 'Suitcases & Travel', 'luggage', nameSw: 'Masanduku ya Safari'),
    ],
    brands: [
      TaxonomyBrand('nike', 'Nike'),
      TaxonomyBrand('adidas', 'Adidas'),
      TaxonomyBrand('puma', 'Puma'),
      TaxonomyBrand('reebok', 'Reebok'),
      TaxonomyBrand('newbalance', 'New Balance'),
      TaxonomyBrand('vans', 'Vans'),
      TaxonomyBrand('converse', 'Converse'),
      TaxonomyBrand('crocs', 'Crocs'),
      TaxonomyBrand('bata', 'Bata'),
      TaxonomyBrand('clarks', 'Clarks'),
    ],
    filters: [
      TaxFilter(key: 'size', labelKey: 'size', options: ['38', '39', '40', '41', '42', '43', '44', '45']),
      TaxFilter(key: 'color', labelKey: 'color', options: ['Black', 'White', 'Brown', 'Blue', 'Red', 'Grey', 'Multi']),
      TaxFilter(key: 'material', labelKey: 'material', options: ['Leather', 'Canvas', 'Synthetic', 'Rubber']),
    ],
    popularFilters: ['topRated', 'verified'],
  ),
  TaxonomyCategory(
    id: 'health',
    name: 'Beauty & Personal Care',
    nameSw: 'Urembo na Utunzaji',
    icon: 'spa',
    image: 'assets/images/categories/health.jpg',
    order: 6,
    popular: true,
    aliases: ['Health & Beauty', 'Health'],
    subs: [
      TaxonomySub('skincare', 'Skincare', 'spa', nameSw: 'Utunzaji wa Ngozi', aliases: ['Skincare']),
      TaxonomySub('makeup', 'Makeup', 'makeup', nameSw: 'Vipodozi', aliases: ['Makeup']),
      TaxonomySub('haircare', 'Hair Care', 'hair', nameSw: 'Utunzaji wa Nywele', aliases: ['Hair Care']),
      TaxonomySub('fragrance', 'Fragrances', 'perfume', nameSw: 'Manukato'),
      TaxonomySub('bath', 'Bath & Body', 'bath', nameSw: 'Kuoga na Mwili'),
      TaxonomySub('hygiene', 'Personal Hygiene', 'hygiene', nameSw: 'Usafi wa Mwili'),
    ],
    brands: [
      TaxonomyBrand('nivea', 'Nivea'),
      TaxonomyBrand('loreal', 'L\'Oreal'),
      TaxonomyBrand('maybelline', 'Maybelline'),
      TaxonomyBrand('garnier', 'Garnier'),
      TaxonomyBrand('dove', 'Dove'),
      TaxonomyBrand('vaseline', 'Vaseline'),
      TaxonomyBrand('olay', 'Olay'),
      TaxonomyBrand('mac', 'MAC'),
    ],
    filters: [],
    popularFilters: ['topRated', 'verified'],
  ),
  TaxonomyCategory(
    id: 'home_garden',
    name: 'Home & Furniture',
    nameSw: 'Nyumba na Samani',
    icon: 'chair',
    image: 'assets/images/categories/home_garden.jpg',
    order: 7,
    popular: true,
    aliases: ['Home & Garden', 'Home'],
    subs: [
      TaxonomySub('sofas', 'Sofas', 'sofa', nameSw: 'Sofa', aliases: ['Furniture']),
      TaxonomySub('beds', 'Beds & Mattresses', 'bed', nameSw: 'Vitanda na Magodoro'),
      TaxonomySub('tables', 'Tables & Chairs', 'chair', nameSw: 'Meza na Viti'),
      TaxonomySub('wardrobes', 'Wardrobes & Storage', 'wardrobe', nameSw: 'Makabati'),
      TaxonomySub('bedding', 'Curtains & Bedding', 'bedding', nameSw: 'Mapazia na Mashuka'),
      TaxonomySub('decor', 'Home Decor', 'decor', nameSw: 'Mapambo ya Nyumba', aliases: ['Home Decor']),
      TaxonomySub('lighting', 'Lighting', 'lamp', nameSw: 'Taa'),
    ],
    brands: [
      TaxonomyBrand('ikea', 'IKEA'),
      TaxonomyBrand('ashley', 'Ashley'),
      TaxonomyBrand('homecentre', 'Home Centre'),
      TaxonomyBrand('nilkamal', 'Nilkamal'),
      TaxonomyBrand('damro', 'Damro'),
    ],
    filters: [
      TaxFilter(key: 'material', labelKey: 'material', options: ['Wood', 'Metal', 'Fabric', 'Leather', 'Plastic', 'Rattan']),
      TaxFilter(key: 'color', labelKey: 'color', options: ['Black', 'White', 'Brown', 'Grey', 'Beige', 'Multi']),
    ],
    popularFilters: ['topRated', 'verified'],
  ),
  TaxonomyCategory(
    id: 'kitchen',
    name: 'Kitchen & Household',
    nameSw: 'Jikoni na Nyumbani',
    icon: 'kitchen',
    image: 'assets/images/categories/kitchen.jpg',
    order: 8,
    subs: [
      TaxonomySub('cookware', 'Cookware & Pots', 'pots', nameSw: 'Vyungu na Sufuria', aliases: ['Kitchen & Dining']),
      TaxonomySub('appliances', 'Kitchen Appliances', 'blender', nameSw: 'Vifaa vya Jikoni'),
      TaxonomySub('utensils', 'Utensils & Cutlery', 'utensils', nameSw: 'Vyombo'),
      TaxonomySub('storage_food', 'Food Storage', 'storage', nameSw: 'Hifadhi ya Chakula'),
      TaxonomySub('cleaning', 'Cleaning Supplies', 'cleaning', nameSw: 'Vifaa vya Usafi'),
    ],
    brands: [
      TaxonomyBrand('von', 'Von Hotpoint'),
      TaxonomyBrand('mika', 'Mika'),
      TaxonomyBrand('binatone', 'Binatone'),
      TaxonomyBrand('philips', 'Philips'),
      TaxonomyBrand('tefal', 'Tefal'),
      TaxonomyBrand('prestige', 'Prestige'),
      TaxonomyBrand('kenwood', 'Kenwood'),
    ],
    filters: [
      TaxFilter(key: 'material', labelKey: 'material', options: ['Stainless Steel', 'Aluminium', 'Non-stick', 'Plastic', 'Glass']),
    ],
    popularFilters: ['topRated', 'verified'],
  ),
  TaxonomyCategory(
    id: 'automotive',
    name: 'Vehicles & Motorcycles',
    nameSw: 'Magari na Pikipiki',
    icon: 'car',
    image: 'assets/images/categories/automotive.jpg',
    order: 9,
    popular: true,
    aliases: ['Automotive'],
    subs: [
      TaxonomySub('cars', 'Cars', 'car', nameSw: 'Magari', aliases: ['All Cars']),
      TaxonomySub('motorcycles', 'Motorcycles', 'motorbike', nameSw: 'Pikipiki', aliases: ['Motorcycles']),
      TaxonomySub('trucks', 'Trucks & Heavy Duty', 'truck', nameSw: 'Malori'),
      TaxonomySub('car_parts', 'Car Parts', 'parts', nameSw: 'Vipuri vya Gari', aliases: ['Car Parts']),
      TaxonomySub('moto_parts', 'Motorcycle Parts', 'parts', nameSw: 'Vipuri vya Pikipiki'),
      TaxonomySub('tyres', 'Tyres & Wheels', 'tyre', nameSw: 'Matairi'),
      TaxonomySub('car_elex', 'Car Electronics', 'devices', nameSw: 'Vifaa vya Gari', aliases: ['Car Accessories']),
    ],
    brands: [
      TaxonomyBrand('toyota', 'Toyota'),
      TaxonomyBrand('nissan', 'Nissan'),
      TaxonomyBrand('honda', 'Honda'),
      TaxonomyBrand('mercedes', 'Mercedes-Benz'),
      TaxonomyBrand('bmw', 'BMW'),
      TaxonomyBrand('vw', 'Volkswagen'),
      TaxonomyBrand('mazda', 'Mazda'),
      TaxonomyBrand('mitsubishi', 'Mitsubishi'),
      TaxonomyBrand('subaru', 'Subaru'),
      TaxonomyBrand('suzuki', 'Suzuki'),
      TaxonomyBrand('yamaha', 'Yamaha'),
      TaxonomyBrand('bajaj', 'Bajaj'),
      TaxonomyBrand('tvs', 'TVS'),
      TaxonomyBrand('haojue', 'Haojue'),
    ],
    filters: [
      TaxFilter(key: 'year', labelKey: 'year', options: ['2020+', '2015-2019', '2010-2014', 'Before 2010']),
      TaxFilter(key: 'mileage', labelKey: 'mileage', options: ['Under 50k km', '50k-100k km', 'Over 100k km']),
      TaxFilter(key: 'fuel', labelKey: 'fuel_type', options: ['Petrol', 'Diesel', 'Hybrid', 'Electric']),
      TaxFilter(key: 'transmission', labelKey: 'transmission', options: ['Manual', 'Automatic']),
    ],
    popularFilters: ['verified', 'topRated'],
  ),
  TaxonomyCategory(
    id: 'business',
    name: 'Building & Hardware',
    nameSw: 'Ujenzi na Vifaa',
    icon: 'construction',
    image: 'assets/images/categories/building.jpg',
    order: 10,
    aliases: ['Business & Industrial', 'Business'],
    subs: [
      TaxonomySub('cement', 'Cement & Concrete', 'cement', nameSw: 'Saruji', aliases: ['Machinery']),
      TaxonomySub('paint', 'Paint', 'paint', nameSw: 'Rangi'),
      TaxonomySub('plumbing', 'Plumbing', 'plumbing', nameSw: 'Mabomba'),
      TaxonomySub('wiring', 'Wiring & Switches', 'devices', nameSw: 'Waya na Swichi'),
      TaxonomySub('tools', 'Tools & Equipment', 'tools', nameSw: 'Zana', aliases: ['Tools & Equipment', 'DIY Tools']),
      TaxonomySub('doors', 'Doors & Windows', 'door', nameSw: 'Milango na Madirisha'),
      TaxonomySub('tiles', 'Tiles & Flooring', 'tiles', nameSw: 'Vigae'),
    ],
    brands: [
      TaxonomyBrand('dangote', 'Dangote'),
      TaxonomyBrand('twiga', 'Twiga'),
      TaxonomyBrand('bamburi', 'Bamburi'),
      TaxonomyBrand('crown', 'Crown Paints'),
      TaxonomyBrand('plascon', 'Plascon'),
      TaxonomyBrand('sadolin', 'Sadolin'),
      TaxonomyBrand('bosch', 'Bosch'),
      TaxonomyBrand('makita', 'Makita'),
      TaxonomyBrand('dewalt', 'DeWalt'),
    ],
    filters: [],
    popularFilters: ['verified', 'topRated'],
  ),
  TaxonomyCategory(
    id: 'agriculture',
    name: 'Agriculture & Farming',
    nameSw: 'Kilimo na Ufugaji',
    icon: 'agriculture',
    image: 'assets/images/categories/agriculture.jpg',
    order: 11,
    aliases: ['Agriculture'],
    subs: [
      TaxonomySub('tractors', 'Tractors & Machinery', 'tractor', nameSw: 'Matrekta', aliases: ['Agriculture']),
      TaxonomySub('seeds', 'Seeds & Seedlings', 'seeds', nameSw: 'Mbegu'),
      TaxonomySub('fertilizer', 'Fertilizers', 'fertilizer', nameSw: 'Mbolea'),
      TaxonomySub('feeds', 'Animal Feeds', 'feeds', nameSw: 'Chakula cha Mifugo'),
      TaxonomySub('irrigation', 'Irrigation', 'irrigation', nameSw: 'Umwagiliaji'),
      TaxonomySub('farmtools', 'Farm Tools', 'tools', nameSw: 'Zana za Shamba'),
    ],
    brands: [
      TaxonomyBrand('massey', 'Massey Ferguson'),
      TaxonomyBrand('johndeere', 'John Deere'),
      TaxonomyBrand('newholland', 'New Holland'),
      TaxonomyBrand('sonalika', 'Sonalika'),
      TaxonomyBrand('valtra', 'Valtra'),
      TaxonomyBrand('yara', 'Yara'),
      TaxonomyBrand('syngenta', 'Syngenta'),
    ],
    filters: [],
    popularFilters: ['verified', 'topRated'],
  ),
  TaxonomyCategory(
    id: 'food',
    name: 'Food & Beverages',
    nameSw: 'Chakula na Vinywaji',
    icon: 'fastfood',
    image: 'assets/images/categories/food.jpg',
    order: 12,
    aliases: ['Food'],
    subs: [
      TaxonomySub('grains', 'Grains & Flour', 'grains', nameSw: 'Nafaka na Unga', aliases: ['Groceries']),
      TaxonomySub('oil', 'Cooking Oil', 'oil', nameSw: 'Mafuta ya Kupikia'),
      TaxonomySub('spices', 'Spices', 'spices', nameSw: 'Viungo', aliases: ['Spices & Herbs']),
      TaxonomySub('snacks', 'Snacks & Sweets', 'snacks', nameSw: 'Vitafunio', aliases: ['Snacks & Sweets']),
      TaxonomySub('beverages', 'Beverages', 'beverages', nameSw: 'Vinywaji', aliases: ['Beverages']),
      TaxonomySub('produce', 'Fresh Produce', 'produce', nameSw: 'Mboga na Matunda'),
      TaxonomySub('dairy', 'Dairy & Eggs', 'dairy', nameSw: 'Maziwa na Mayai'),
    ],
    brands: [
      TaxonomyBrand('azam', 'Azam'),
      TaxonomyBrand('bakhresa', 'Bakhresa'),
      TaxonomyBrand('tangafresh', 'Tanga Fresh'),
      TaxonomyBrand('asas', 'ASAS'),
      TaxonomyBrand('supa', 'Supa'),
    ],
    filters: [],
    popularFilters: ['topRated', 'verified'],
  ),
  TaxonomyCategory(
    id: 'maternal',
    name: 'Baby, Kids & Toys',
    nameSw: 'Watoto na Vichezeo',
    icon: 'child_care',
    image: 'assets/images/categories/maternal.jpg',
    order: 13,
    aliases: ['Maternal & Kids', 'Kids, Baby & Maternity', 'Kids'],
    subs: [
      TaxonomySub('diapers', 'Diapers & Wipes', 'diapers', nameSw: 'Nephi', aliases: ['Baby Care']),
      TaxonomySub('babycloth', 'Baby Clothing', 'babycloth', nameSw: 'Nguo za Watoto', aliases: ['Kids Fashion']),
      TaxonomySub('babyfood', 'Baby Food & Formula', 'babyfood', nameSw: 'Chakula cha Watoto'),
      TaxonomySub('strollers', 'Strollers & Carriers', 'stroller', nameSw: 'Mikokoteni ya Watoto'),
      TaxonomySub('toys', 'Toys', 'toys', nameSw: 'Vichezeo', aliases: ['Kids Toys', 'Games & Toys']),
      TaxonomySub('kidsfurniture', 'Kids Furniture', 'chair', nameSw: 'Samani za Watoto'),
    ],
    brands: [
      TaxonomyBrand('pampers', 'Pampers'),
      TaxonomyBrand('huggies', 'Huggies'),
      TaxonomyBrand('johnsons', 'Johnson\'s'),
      TaxonomyBrand('avent', 'Philips Avent'),
      TaxonomyBrand('tommee', 'Tommee Tippee'),
      TaxonomyBrand('lego', 'LEGO'),
      TaxonomyBrand('fisherprice', 'Fisher-Price'),
      TaxonomyBrand('chicco', 'Chicco'),
    ],
    filters: [
      TaxFilter(key: 'size', labelKey: 'size', options: ['Newborn', '0-6M', '6-12M', '1-2Y', '3-4Y', '5+Y']),
      TaxFilter(key: 'gender', labelKey: 'gender', options: ['Boys', 'Girls', 'Unisex']),
    ],
    popularFilters: ['topRated', 'verified'],
  ),
  TaxonomyCategory(
    id: 'sports',
    name: 'Sports & Outdoors',
    nameSw: 'Michezo',
    icon: 'soccer',
    image: 'assets/images/categories/sports.jpg',
    order: 14,
    aliases: ['Sports & Entertainment', 'Sports'],
    subs: [
      TaxonomySub('fitness', 'Fitness Equipment', 'fitness', nameSw: 'Vifaa vya Mazoezi', aliases: ['Fitness']),
      TaxonomySub('football', 'Football', 'soccer', nameSw: 'Mpira wa Miguu'),
      TaxonomySub('basketball', 'Basketball', 'basketball', nameSw: 'Mpira wa Kikapu'),
      TaxonomySub('bicycles', 'Bicycles', 'bicycle', nameSw: 'Baiskeli'),
      TaxonomySub('camping', 'Camping & Outdoor', 'camping', nameSw: 'Kambi', aliases: ['Outdoor Sports']),
      TaxonomySub('racket', 'Racket Sports', 'racket', nameSw: 'Tenis na Badminton'),
    ],
    brands: [
      TaxonomyBrand('nike', 'Nike'),
      TaxonomyBrand('adidas', 'Adidas'),
      TaxonomyBrand('puma', 'Puma'),
      TaxonomyBrand('reebok', 'Reebok'),
      TaxonomyBrand('spalding', 'Spalding'),
      TaxonomyBrand('mikasa', 'Mikasa'),
      TaxonomyBrand('wilson', 'Wilson'),
    ],
    filters: [],
    popularFilters: ['topRated', 'verified'],
  ),
  TaxonomyCategory(
    id: 'books',
    name: 'Books & Stationery',
    nameSw: 'Vitabu',
    icon: 'book',
    image: 'assets/images/categories/books.jpg',
    order: 15,
    subs: [
      TaxonomySub('textbooks', 'Textbooks', 'book', nameSw: 'Vitabu vya Shule'),
      TaxonomySub('novels', 'Novels & Storybooks', 'novel', nameSw: 'Riwaya'),
      TaxonomySub('religious', 'Religious Books', 'religious', nameSw: 'Vitabu vya Dini'),
      TaxonomySub('kidsbooks', 'Children\'s Books', 'kidsbook', nameSw: 'Vitabu vya Watoto', aliases: ['Books & Media']),
      TaxonomySub('office_stat', 'Office Stationery', 'stationery', nameSw: 'Vifaa vya Ofisi', aliases: ['Office Supplies']),
      TaxonomySub('school_stat', 'School Stationery', 'pencil', nameSw: 'Vifaa vya Shule'),
      TaxonomySub('art_sup', 'Art Supplies', 'palette', nameSw: 'Vifaa vya Sanaa'),
    ],
    brands: [
      TaxonomyBrand('oxford', 'Oxford'),
      TaxonomyBrand('cambridge', 'Cambridge'),
      TaxonomyBrand('longhorn', 'Longhorn'),
      TaxonomyBrand('nataraj', 'Nataraj'),
      TaxonomyBrand('staedtler', 'Staedtler'),
      TaxonomyBrand('faber', 'Faber-Castell'),
      TaxonomyBrand('bic', 'BIC'),
      TaxonomyBrand('deli', 'Deli'),
    ],
    filters: [],
    popularFilters: ['topRated', 'verified'],
  ),
  TaxonomyCategory(
    id: 'jewelry',
    name: 'Jewelry & Accessories',
    nameSw: 'Vito na Mapambo',
    icon: 'diamond',
    image: 'assets/images/categories/jewelry.jpg',
    order: 16,
    subs: [
      TaxonomySub('necklaces', 'Necklaces', 'necklace', nameSw: 'Shanga', aliases: ['Jewelry']),
      TaxonomySub('rings', 'Rings', 'ring', nameSw: 'Pete'),
      TaxonomySub('earrings', 'Earrings', 'earrings', nameSw: 'Herini'),
      TaxonomySub('bracelets', 'Bracelets', 'bracelet', nameSw: 'Bangili'),
      TaxonomySub('watches', 'Watches', 'watch', nameSw: 'Saa'),
      TaxonomySub('sunglasses', 'Sunglasses', 'sunglasses', nameSw: 'Miwani ya Jua'),
    ],
    brands: [
      TaxonomyBrand('pandora', 'Pandora'),
      TaxonomyBrand('swarovski', 'Swarovski'),
      TaxonomyBrand('casio', 'Casio'),
      TaxonomyBrand('fossil', 'Fossil'),
      TaxonomyBrand('dw', 'Daniel Wellington'),
      TaxonomyBrand('gshock', 'G-Shock'),
    ],
    filters: [
      TaxFilter(key: 'material', labelKey: 'material', options: ['Gold', 'Silver', 'Stainless Steel', 'Beads', 'Leather']),
    ],
    popularFilters: ['topRated', 'verified'],
  ),
  TaxonomyCategory(
    id: 'solar',
    name: 'Electrical & Solar',
    nameSw: 'Umeme na Sola',
    icon: 'solar',
    image: 'assets/images/categories/solar.jpg',
    order: 17,
    subs: [
      TaxonomySub('panels', 'Solar Panels', 'solar', nameSw: 'Paneli za Sola'),
      TaxonomySub('batteries', 'Solar Batteries', 'battery', nameSw: 'Betri za Sola'),
      TaxonomySub('inverters', 'Inverters', 'inverter', nameSw: 'Inverter'),
      TaxonomySub('solarlights', 'Solar Lights', 'lamp', nameSw: 'Taa za Sola'),
      TaxonomySub('generators', 'Generators', 'generator', nameSw: 'Jenereta'),
      TaxonomySub('cables', 'Cables & Wiring', 'devices', nameSw: 'Nyaya'),
    ],
    brands: [
      TaxonomyBrand('sunking', 'Sun King'),
      TaxonomyBrand('dlight', 'D.Light'),
      TaxonomyBrand('mkopa', 'M-Kopa'),
      TaxonomyBrand('zola', 'Zola Electric'),
      TaxonomyBrand('jinko', 'JinkoSolar'),
      TaxonomyBrand('jasolar', 'JA Solar'),
      TaxonomyBrand('canadian', 'Canadian Solar'),
    ],
    filters: [],
    popularFilters: ['verified', 'topRated'],
  ),
  TaxonomyCategory(
    id: 'hobbies',
    name: 'Hobbies, Arts & Crafts',
    nameSw: 'Sanaa na Ufundi',
    icon: 'palette',
    image: 'assets/images/categories/hobbies.jpg',
    order: 18,
    subs: [
      TaxonomySub('instruments', 'Musical Instruments', 'guitar', nameSw: 'Ala za Muziki'),
      TaxonomySub('painting', 'Art & Painting', 'palette', nameSw: 'Uchoraji'),
      TaxonomySub('boardgames', 'Board Games', 'games', nameSw: 'Michezo ya Bodi'),
      TaxonomySub('collectibles', 'Collectibles', 'collectibles', nameSw: 'Vitu vya Kukusanya'),
      TaxonomySub('crafts', 'Craft Materials', 'crafts', nameSw: 'Vifaa vya Ufundi'),
    ],
    brands: [
      TaxonomyBrand('yamaha', 'Yamaha'),
      TaxonomyBrand('fender', 'Fender'),
      TaxonomyBrand('casio', 'Casio'),
      TaxonomyBrand('faber', 'Faber-Castell'),
      TaxonomyBrand('staedtler', 'Staedtler'),
      TaxonomyBrand('lego', 'LEGO'),
    ],
    filters: [],
    popularFilters: ['topRated', 'verified'],
  ),
  TaxonomyCategory(
    id: 'pets',
    name: 'Pets & Animals',
    nameSw: 'Wanyama',
    icon: 'pets',
    image: 'assets/images/categories/pets.jpg',
    order: 19,
    subs: [
      TaxonomySub('dogs', 'Dogs', 'dog', nameSw: 'Mbwa'),
      TaxonomySub('cats', 'Cats', 'cat', nameSw: 'Paka'),
      TaxonomySub('birds', 'Birds', 'bird', nameSw: 'Ndege'),
      TaxonomySub('fish', 'Fish & Aquariums', 'fish', nameSw: 'Samaki'),
      TaxonomySub('petfood', 'Pet Food', 'petfood', nameSw: 'Chakula cha Wanyama'),
      TaxonomySub('petacc', 'Pet Accessories', 'package', nameSw: 'Vifaa vya Wanyama'),
    ],
    brands: [
      TaxonomyBrand('royalcanin', 'Royal Canin'),
      TaxonomyBrand('pedigree', 'Pedigree'),
      TaxonomyBrand('whiskas', 'Whiskas'),
      TaxonomyBrand('purina', 'Purina'),
      TaxonomyBrand('drools', 'Drools'),
    ],
    filters: [],
    popularFilters: ['topRated', 'verified'],
  ),
  TaxonomyCategory(
    id: 'services',
    name: 'Physical Services',
    nameSw: 'Huduma',
    icon: 'handyman',
    image: 'assets/images/categories/services.jpg',
    order: 20,
    aliases: ['Services'],
    subs: [
      TaxonomySub('repair', 'Repair & Maintenance', 'handyman', nameSw: 'Ukarabati', aliases: ['Repair & Maintenance']),
      TaxonomySub('tailoring', 'Tailoring & Design', 'tailoring', nameSw: 'Ushonaji'),
      TaxonomySub('photo', 'Photography & Video', 'camera', nameSw: 'Upigaji Picha'),
      TaxonomySub('cleaning', 'Cleaning Services', 'cleaning', nameSw: 'Usafi'),
      TaxonomySub('salon', 'Beauty Services', 'spa', nameSw: 'Saluni'),
      TaxonomySub('transport', 'Transport & Moving', 'truck', nameSw: 'Usafiri'),
      TaxonomySub('install', 'Installation', 'tools', nameSw: 'Ufungaji'),
      TaxonomySub('tutoring', 'In-Person Tutoring', 'book', nameSw: 'Mafunzo ya Ana kwa Ana'),
      TaxonomySub('fundi', 'Construction & Fundi', 'construction', nameSw: 'Ujenzi na Mafundi', aliases: ['Home Services', 'Education & Training']),
      TaxonomySub('events', 'Events & Catering', 'events', nameSw: 'Matukio'),
    ],
    brands: [],
    filters: [
      TaxFilter(key: 'availability', labelKey: 'availability', options: ['Weekdays', 'Weekends', 'Anytime', 'Emergency']),
    ],
    popularFilters: ['verified', 'topRated'],
  ),
];

/// Lookup by stable id.
TaxonomyCategory? taxonomyById(String id) {
  for (final c in kMarketplaceTaxonomy) {
    if (c.id == id) return c;
  }
  return null;
}

/// Resolves a stored category or subcategory name (current or legacy)
/// to its taxonomy entry.
TaxonomyCategory? resolveTaxonomyByName(String name) {
  final key = name.trim().toLowerCase();
  if (key.isEmpty) return null;
  for (final c in kMarketplaceTaxonomy) {
    if (c.name.toLowerCase() == key || c.nameSw.toLowerCase() == key) {
      return c;
    }
    for (final a in c.aliases) {
      if (a.toLowerCase() == key) return c;
    }
  }
  for (final c in kMarketplaceTaxonomy) {
    for (final s in c.subs) {
      if (s.name.toLowerCase() == key || s.nameSw.toLowerCase() == key) {
        return c;
      }
      for (final a in s.aliases) {
        if (a.toLowerCase() == key) return c;
      }
    }
  }
  return null;
}
