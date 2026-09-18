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

  it('combines the full-text q into AND filters', () => {
    const where = buildListWhere({ q: 'simu' });
    assert.deepEqual(where.AND, [
      {
        OR: [
          { title: { contains: 'simu', mode: 'insensitive' } },
          { description: { contains: 'simu', mode: 'insensitive' } },
        ],
      },
    ]);
  });

  it('omits AND when nothing is being filtered', () => {
    const where = buildListWhere({ q: undefined, ids: [] });
    assert.equal(where.AND, undefined);
    assert.equal(where.OR, undefined);
  });

  it('narrows to a seller profile once it is resolved', () => {
    const where = buildListWhere({ sellerProfileId: 'seller-1' });
    assert.equal(where.sellerId, 'seller-1');
  });

  it('matches a batch of ids typed as uuid, slug, and legacy Firestore id', () => {
    const uuid = '27087889-9319-4ddf-ae3a-32936d3e2595';
    const where = buildListWhere({ ids: [uuid, 'bmw-m4-9249db', 'QoiW3T1zhXS1HCsvHmYv'] });
    assert.deepEqual(where.AND, [
      {
        OR: [
          { id: { in: [uuid] } },
          { slug: { in: ['bmw-m4-9249db', 'QoiW3T1zhXS1HCsvHmYv'] } },
          { snapshot: { path: ['legacyId'], equals: uuid } },
          { snapshot: { path: ['legacyId'], equals: 'bmw-m4-9249db' } },
          { snapshot: { path: ['legacyId'], equals: 'QoiW3T1zhXS1HCsvHmYv' } },
        ],
      },
    ]);
  });

  it('keeps the slug/legacy branch even when every id is a uuid', () => {
    const uuid = '27087889-9319-4ddf-ae3a-32936d3e2595';
    const where = buildListWhere({ ids: [uuid] });
    assert.deepEqual(where.AND, [
      {
        OR: [
          { id: { in: [uuid] } },
          { snapshot: { path: ['legacyId'], equals: uuid } },
        ],
      },
    ]);
  });

  it('ignores id batch matching when no ids are given', () => {
    const where = buildListWhere({ ids: [] });
    assert.equal(where.AND, undefined);
  });
});