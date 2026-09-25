// Seeds default marketplace categories (idempotent by slug).
const { getPrisma } = require('../config/database');

const DEFAULTS = [
  'Electronics',
  'Phones & Tablets',
  'Fashion',
  'Home & Living',
  'Beauty & Personal Care',
  'Vehicles & Parts',
  'Agriculture',
  'Food & Groceries',
  'Sports & Outdoors',
  'Baby & Kids',
  'Business & Office',
  'Hardware & Tools',
  'Other Products',
];

async function seedCategories() {
  const prisma = getPrisma();
  // Keep legacy service listings in the database for history, but remove the
  // category from the public physical-product catalog.
  await prisma.category.updateMany({
    where: { slug: { in: ['services', 'service'] } },
    data: { isActive: false },
  });

  let created = 0;
  for (let i = 0; i < DEFAULTS.length; i++) {
    const name = DEFAULTS[i];
    const slug = name.toLowerCase().replace(/[^a-z0-9]+/g, '-');
    const existing = await prisma.category.findUnique({ where: { slug } });
    if (!existing) {
      await prisma.category.create({ data: { name, slug, sortOrder: i, isActive: true } });
      created++;
    }
  }
  return { total: DEFAULTS.length, created };
}

if (require.main === module) {
  seedCategories()
    .then((r) => {
      console.log(`categories: total=${r.total} created=${r.created}`);
      process.exit(0);
    })
    .catch((e) => {
      console.error('seed failed:', e.message);
      process.exit(1);
    });
}

module.exports = { seedCategories, DEFAULTS };
