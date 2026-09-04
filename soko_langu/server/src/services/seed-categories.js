// Seeds default marketplace categories (idempotent by slug).
const { getPrisma } = require('../config/database');

const DEFAULTS = [
  'Fashion',
  'Electronics',
  'Phones',
  'Computers',
  'Beauty',
  'Home',
  'Vehicles',
  'Agriculture',
  'Food',
  'Services',
  'Accessories',
  'Other',
];

async function seedCategories() {
  const prisma = getPrisma();
  let created = 0;
  for (let i = 0; i < DEFAULTS.length; i++) {
    const name = DEFAULTS[i];
    const slug = name.toLowerCase().replace(/[^a-z0-9]+/g, '-');
    const existing = await prisma.category.findUnique({ where: { slug } });
    if (!existing) {
      await prisma.category.create({ data: { name, slug, sortOrder: i } });
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
