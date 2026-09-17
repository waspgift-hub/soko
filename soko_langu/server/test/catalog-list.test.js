const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { buildListWhere } = require('../src/modules/products/product-service');

describe('buildListWhere', () => {
  it('bounds the query to published, non-deleted products', () => {
    assert.deepEqual(buildListWhere({}), { status: 'published', deletedAt: null });
  });

  it('filters by categoryId and price range', () => {
    const where = buildListWhere({
      categoryId: '00000000-0000-4000-8000-000000000001',
      minPrice: 1000,
      maxPrice: 500000,
    });
    assert.equal(where.categoryId, '00000000-0000-4000-8000-000000000001');
    assert.deepEqual(where.price, { gte: 1000n, lte: 500000n });
  });

  it('maps boosted/featured to snapshot JSON path probes', () => {
    const where = buildListWhere({ boosted: true, featured: true });
    assert.deepEqual(where.AND, [
      { snapshot: { path: ['isBoosted'], equals: true } },
      { snapshot: { path: ['isFeatured'], equals: true } },
    ]);
  });

  it('exact-matches subcategory inside snapshot', () => {
    const where = buildListWhere({ subcategory: 'Smartphones' });
    assert.deepEqual(where.AND, [
      { snapshot: { path: ['subcategory'], equals: 'Smartphones' } },
    ]);
  });

  it('omits AND when no snapshot filters are requested', () => {
    const where = buildListWhere({ q: 'simu' });
    assert.equal(where.AND, undefined);
    assert.deepEqual(where.OR, [
      { title: { contains: 'simu', mode: 'insensitive' } },
      { description: { contains: 'simu', mode: 'insensitive' } },
    ]);
  });
});