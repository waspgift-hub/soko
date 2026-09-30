// Seeds the canonical marketplace taxonomy into Firestore `categories`.
//
// Mirrors lib/data/marketplace_taxonomy.dart (the single source of truth the
// Flutter app falls back to offline). The v1 GET /products/categories route
// only returns rows with isActive:true, so every doc here must be active or
// the home category grid renders empty. Doc ids are stable slugs: root id = taxonomy id, child id = "<root>__<sub>" because sub slugs
// (e.g. "cleaning") repeat across parents and Firestore ids are global.
require('dotenv').config();

const { getStore } = require('../config/database');

const TAXONOMY = [
  {
    id: 'electronics', name: 'Electronics & Technology', nameSw: 'Elektroniki na Teknolojia',
    image: 'assets/images/categories/electronics.jpg', order: 1,
    subs: [
      ['tvs', 'TVs', 'TV'],
      ['audio', 'Audio & Speakers', 'Sauti na Spika'],
      ['cameras', 'Cameras & Drones', 'Kamera na Droni'],
      ['wearables', 'Wearables', 'Vivaa Janja'],
      ['gaming', 'Gaming Consoles', 'Michezo ya Video'],
      ['networking', 'Networking', 'Mitandao'],
      ['elec_accessories', 'Accessories', 'Vifaa'],
    ],
  },
  {
    id: 'computers', name: 'Computers & Office', nameSw: 'Kompyuta na Ofisi',
    image: 'assets/images/categories/computers.jpg', order: 2,
    subs: [
      ['laptops', 'Laptops', 'Laptop'],
      ['desktops', 'Desktops', 'Desktop'],
      ['monitors', 'Monitors', 'Monitor'],
      ['printers', 'Printers & Copiers', 'Printa'],
      ['storage', 'Storage & Memory', 'Hifadhi Data'],
      ['comp_accessories', 'Keyboards & Mice', 'Kibodi na Mausi'],
    ],
  },
  {
    id: 'phones', name: 'Phones & Accessories', nameSw: 'Simu na Vifaa',
    image: 'assets/images/categories/phones.jpg', order: 3,
    subs: [
      ['smartphones', 'Smartphones', 'Simu Janja'],
      ['feature_phones', 'Feature Phones', 'Simu za Kawaida'],
      ['cases', 'Cases & Covers', 'Kava za Simu'],
      ['chargers', 'Chargers & Cables', 'Chaja na Nyaya'],
      ['powerbanks', 'Power Banks', 'Power Bank'],
      ['earphones', 'Earphones & Earbuds', 'Earphones'],
      ['smartwatches', 'Smart Watches', 'Saa Janja'],
    ],
  },
  {
    id: 'fashion', name: 'Fashion & Clothing', nameSw: 'Mavazi',
    image: 'assets/images/categories/fashion.jpg', order: 4,
    subs: [
      ['menswear', "Men's Clothing", 'Mavazi ya Wanaume'],
      ['womenswear', "Women's Clothing", 'Mavazi ya Wanawake'],
      ['traditional', 'Traditional Wear', 'Vitenge na Kanzu'],
      ['suits', 'Suits & Blazers', 'Suti'],
      ['tops', 'T-Shirts & Tops', 'Tisheti'],
      ['jeans', 'Jeans & Trousers', 'Jeans na Suruali'],
      ['dresses', 'Dresses & Skirts', 'Magauni na Sketi'],
    ],
  },
  {
    id: 'shoes_bags', name: 'Shoes & Bags', nameSw: 'Viatu na Mifuko',
    image: 'assets/images/categories/shoes_bags.jpg', order: 5,
    subs: [
      ['sneakers', 'Sneakers', 'Sneakers'],
      ['mens_shoes', "Men's Shoes", 'Viatu vya Wanaume'],
      ['womens_shoes', "Women's Shoes", 'Viatu vya Wanawake'],
      ['sandals', 'Sandals & Slippers', 'Ndala'],
      ['handbags', 'Handbags', 'Mikoba'],
      ['backpacks', 'Backpacks', 'Mabegi ya Mgongo'],
      ['luggage', 'Suitcases & Travel', 'Masanduku ya Safari'],
    ],
  },
  {
    id: 'health', name: 'Beauty & Personal Care', nameSw: 'Urembo na Utunzaji',
    image: 'assets/images/categories/health.jpg', order: 6,
    subs: [
      ['skincare', 'Skincare', 'Utunzaji wa Ngozi'],
      ['makeup', 'Makeup', 'Vipodozi'],
      ['haircare', 'Hair Care', 'Utunzaji wa Nywele'],
      ['fragrance', 'Fragrances', 'Manukato'],
      ['bath', 'Bath & Body', 'Kuoga na Mwili'],
      ['hygiene', 'Personal Hygiene', 'Usafi wa Mwili'],
    ],
  },
  {
    id: 'home_garden', name: 'Home & Furniture', nameSw: 'Nyumba na Samani',
    image: 'assets/images/categories/home_garden.jpg', order: 7,
    subs: [
      ['sofas', 'Sofas', 'Sofa'],
      ['beds', 'Beds & Mattresses', 'Vitanda na Magodoro'],
      ['tables', 'Tables & Chairs', 'Meza na Viti'],
      ['wardrobes', 'Wardrobes & Storage', 'Makabati'],
      ['bedding', 'Curtains & Bedding', 'Mapazia na Mashuka'],
      ['decor', 'Home Decor', 'Mapambo ya Nyumba'],
      ['lighting', 'Lighting', 'Taa'],
    ],
  },
  {
    id: 'kitchen', name: 'Kitchen & Household', nameSw: 'Jikoni na Nyumbani',
    image: 'assets/images/categories/kitchen.jpg', order: 8,
    subs: [
      ['cookware', 'Cookware & Pots', 'Vyungu na Sufuria'],
      ['appliances', 'Kitchen Appliances', 'Vifaa vya Jikoni'],
      ['utensils', 'Utensils & Cutlery', 'Vyombo'],
      ['storage_food', 'Food Storage', 'Hifadhi ya Chakula'],
      ['cleaning', 'Cleaning Supplies', 'Vifaa vya Usafi'],
    ],
  },
  {
    id: 'automotive', name: 'Vehicles & Motorcycles', nameSw: 'Magari na Pikipiki',
    image: 'assets/images/categories/automotive.jpg', order: 9,
    subs: [
      ['cars', 'Cars', 'Magari'],
      ['motorcycles', 'Motorcycles', 'Pikipiki'],
      ['trucks', 'Trucks & Heavy Duty', 'Malori'],
      ['car_parts', 'Car Parts', 'Vipuri vya Gari'],
      ['moto_parts', 'Motorcycle Parts', 'Vipuri vya Pikipiki'],
      ['tyres', 'Tyres & Wheels', 'Matairi'],
      ['car_elex', 'Car Electronics', 'Vifaa vya Gari'],
    ],
  },
  {
    id: 'business', name: 'Building & Hardware', nameSw: 'Ujenzi na Vifaa',
    image: 'assets/images/categories/building.jpg', order: 10,
    subs: [
      ['cement', 'Cement & Concrete', 'Saruji'],
      ['paint', 'Paint', 'Rangi'],
      ['plumbing', 'Plumbing', 'Mabomba'],
      ['wiring', 'Wiring & Switches', 'Waya na Swichi'],
      ['tools', 'Tools & Equipment', 'Zana'],
      ['doors', 'Doors & Windows', 'Milango na Madirisha'],
      ['tiles', 'Tiles & Flooring', 'Vigae'],
    ],
  },
  {
    id: 'agriculture', name: 'Agriculture & Farming', nameSw: 'Kilimo na Ufugaji',
    image: 'assets/images/categories/agriculture.jpg', order: 11,
    subs: [
      ['tractors', 'Tractors & Machinery', 'Matrekta'],
      ['seeds', 'Seeds & Seedlings', 'Mbegu'],
      ['fertilizer', 'Fertilizers', 'Mbolea'],
      ['feeds', 'Animal Feeds', 'Chakula cha Mifugo'],
      ['irrigation', 'Irrigation', 'Umwagiliaji'],
      ['farmtools', 'Farm Tools', 'Zana za Shamba'],
    ],
  },
  {
    id: 'food', name: 'Food & Beverages', nameSw: 'Chakula na Vinywaji',
    image: 'assets/images/categories/food.jpg', order: 12,
    subs: [
      ['grains', 'Grains & Flour', 'Nafaka na Unga'],
      ['oil', 'Cooking Oil', 'Mafuta ya Kupikia'],
      ['spices', 'Spices', 'Viungo'],
      ['snacks', 'Snacks & Sweets', 'Vitafunio'],
      ['beverages', 'Beverages', 'Vinywaji'],
      ['produce', 'Fresh Produce', 'Mboga na Matunda'],
      ['dairy', 'Dairy & Eggs', 'Maziwa na Mayai'],
    ],
  },
  {
    id: 'maternal', name: 'Baby, Kids & Toys', nameSw: 'Watoto na Vichezeo',
    image: 'assets/images/categories/maternal.jpg', order: 13,
    subs: [
      ['diapers', 'Diapers & Wipes', 'Nephi'],
      ['babycloth', 'Baby Clothing', 'Nguo za Watoto'],
      ['babyfood', 'Baby Food & Formula', 'Chakula cha Watoto'],
      ['strollers', 'Strollers & Carriers', 'Mikokoteni ya Watoto'],
      ['toys', 'Toys', 'Vichezeo'],
      ['kidsfurniture', 'Kids Furniture', 'Samani za Watoto'],
    ],
  },
  {
    id: 'sports', name: 'Sports & Outdoors', nameSw: 'Michezo',
    image: 'assets/images/categories/sports.jpg', order: 14,
    subs: [
      ['fitness', 'Fitness Equipment', 'Vifaa vya Mazoezi'],
      ['football', 'Football', 'Mpira wa Miguu'],
      ['basketball', 'Basketball', 'Mpira wa Kikapu'],
      ['bicycles', 'Bicycles', 'Baiskeli'],
      ['camping', 'Camping & Outdoor', 'Kambi'],
      ['racket', 'Racket Sports', 'Tenis na Badminton'],
    ],
  },
  {
    id: 'books', name: 'Books & Stationery', nameSw: 'Vitabu',
    image: 'assets/images/categories/books.jpg', order: 15,
    subs: [
      ['textbooks', 'Textbooks', 'Vitabu vya Shule'],
      ['novels', 'Novels & Storybooks', 'Riwaya'],
      ['religious', 'Religious Books', 'Vitabu vya Dini'],
      ['kidsbooks', "Children's Books", 'Vitabu vya Watoto'],
      ['office_stat', 'Office Stationery', 'Vifaa vya Ofisi'],
      ['school_stat', 'School Stationery', 'Vifaa vya Shule'],
      ['art_sup', 'Art Supplies', 'Vifaa vya Sanaa'],
    ],
  },
  {
    id: 'jewelry', name: 'Jewelry & Accessories', nameSw: 'Vito na Mapambo',
    image: 'assets/images/categories/jewelry.jpg', order: 16,
    subs: [
      ['necklaces', 'Necklaces', 'Shanga'],
      ['rings', 'Rings', 'Pete'],
      ['earrings', 'Earrings', 'Herini'],
      ['bracelets', 'Bracelets', 'Bangili'],
      ['watches', 'Watches', 'Saa'],
      ['sunglasses', 'Sunglasses', 'Miwani ya Jua'],
    ],
  },
  {
    id: 'solar', name: 'Electrical & Solar', nameSw: 'Umeme na Sola',
    image: 'assets/images/categories/solar.jpg', order: 17,
    subs: [
      ['panels', 'Solar Panels', 'Paneli za Sola'],
      ['batteries', 'Solar Batteries', 'Betri za Sola'],
      ['inverters', 'Inverters', 'Inverter'],
      ['solarlights', 'Solar Lights', 'Taa za Sola'],
      ['generators', 'Generators', 'Jenereta'],
      ['cables', 'Cables & Wiring', 'Nyaya'],
    ],
  },
  {
    id: 'hobbies', name: 'Hobbies, Arts & Crafts', nameSw: 'Sanaa na Ufundi',
    image: 'assets/images/categories/hobbies.jpg', order: 18,
    subs: [
      ['instruments', 'Musical Instruments', 'Ala za Muziki'],
      ['painting', 'Art & Painting', 'Uchoraji'],
      ['boardgames', 'Board Games', 'Michezo ya Bodi'],
      ['collectibles', 'Collectibles', 'Vitu vya Kukusanya'],
      ['crafts', 'Craft Materials', 'Vifaa vya Ufundi'],
    ],
  },
  {
    id: 'pets', name: 'Pets & Animals', nameSw: 'Wanyama',
    image: 'assets/images/categories/pets.jpg', order: 19,
    subs: [
      ['dogs', 'Dogs', 'Mbwa'],
      ['cats', 'Cats', 'Paka'],
      ['birds', 'Birds', 'Ndege'],
      ['fish', 'Fish & Aquariums', 'Samaki'],
      ['petfood', 'Pet Food', 'Chakula cha Wanyama'],
      ['petacc', 'Pet Accessories', 'Vifaa vya Wanyama'],
    ],
  },
  {
    id: 'services', name: 'Physical Services', nameSw: 'Huduma',
    image: 'assets/images/categories/services.jpg', order: 20,
    subs: [
      ['repair', 'Repair & Maintenance', 'Ukarabati'],
      ['tailoring', 'Tailoring & Design', 'Ushonaji'],
      ['photo', 'Photography & Video', 'Upigaji Picha'],
      ['cleaning', 'Cleaning Services', 'Usafi'],
      ['salon', 'Beauty Services', 'Saluni'],
      ['transport', 'Transport & Moving', 'Usafiri'],
      ['install', 'Installation', 'Ufungaji'],
      ['tutoring', 'In-Person Tutoring', 'Mafunzo ya Ana kwa Ana'],
      ['fundi', 'Construction & Fundi', 'Ujenzi na Mafundi'],
      ['events', 'Events & Catering', 'Matukio'],
    ],
  },
];

// Seeds idempotently by deterministic doc id, so a child slug reused by two
// roots ("cleaning") stays two distinct docs. All writes flush in ONE
// Firestore batch via $transaction — per-doc round trips would drag a
// 150-doc seed past the CLI timeout.
async function seedCategories() {
  const store = getStore();
  const canonicalRootIds = new Set(TAXONOMY.map((t) => t.id));

  // Baseline scan decides create-vs-update per doc; a re-run never duplicates.
  const all = await store.category.findMany({ where: {} });
  const before = new Set(all.map((r) => String(r.id)));
  const ops = [];

  for (const t of TAXONOMY) {
    const rootData = {
      name: t.name, nameSw: t.nameSw, slug: t.id,
      iconUrl: t.image, sortOrder: t.order,
      parentId: null, isActive: true,
    };
    const rootDoc = {
      model: 'category',
      op: before.has(t.id) ? 'update' : 'create',
      args: before.has(t.id)
        ? { where: { id: t.id }, data: rootData }
        : { data: { ...rootData, id: t.id } },
    };
    ops.push(rootDoc);

    for (let i = 0; i < t.subs.length; i++) {
      const [subId, subName, subNameSw] = t.subs[i];
      const docId = `${t.id}__${subId}`;
      const childData = {
        name: subName, nameSw: subNameSw, slug: subId, parentId: t.id,
        // sortOrder is only meaningful for roots; kept to keep the row shape
        // uniform for the API select.
        sortOrder: i, isActive: true,
      };
      ops.push({
        model: 'category',
        op: before.has(docId) ? 'update' : 'create',
        args: before.has(docId)
          ? { where: { id: docId }, data: childData }
          : { data: { ...childData, id: docId } },
      });
    }
  }

  // Stray active roots (older ad-hoc seeds with random uuid ids) would double
  // in the grid next to the taxonomy. Soft-disable rather than delete so any
  // product history pointing at them keeps resolving.
  let deactivated = 0;
  for (const row of all) {
    const id = String(row.id);
    if (row.parentId == null && row.isActive === true && !canonicalRootIds.has(id)) {
      ops.push({
        model: 'category',
        op: 'update',
        args: { where: { id }, data: { isActive: false } },
      });
      deactivated++;
    }
  }

  await store.$transaction(ops);

  const snap = await store.category.findMany({ where: {} });
  const roots = snap.filter((r) => r.parentId == null);
  const subs = snap.filter((r) => r.parentId != null);
  return {
    rootsCreated: roots.filter((r) => !before.has(String(r.id))).length,
    rootsUpdated: roots.length - roots.filter((r) => !before.has(String(r.id))).length,
    subsCreated: subs.filter((r) => !before.has(String(r.id))).length,
    subsUpdated: subs.length - subs.filter((r) => !before.has(String(r.id))).length,
    deactivated,
  };
}

if (require.main === module) {
  seedCategories()
    .then((r) => {
      console.log(
        `categories seeded: roots ${r.rootsCreated} created / ${r.rootsUpdated} updated, ` +
          `subs ${r.subsCreated} created / ${r.subsUpdated} updated, ` +
          `${r.deactivated} stray roots deactivated`
      );
      process.exit(0);
    })
    .catch((e) => {
      console.error('seed failed:', e.message);
      process.exit(1);
    });
}

module.exports = { seedCategories, TAXONOMY };
