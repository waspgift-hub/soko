const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { mapFirestoreProductToPrisma, mapFirestoreMediaToProductRows, buildSlug, normaliseCondition, toCreatedAt } = require('../src/modules/products/legacy-mapper');

const SELLER_ID = '11111111-1111-1111-1111-111111111111';
const CATEGORY_ID = '22222222-2222-2222-2222-222222222222';

function firestoreDoc(overrides = {}) {
  return {
    name: 'iPhone 15 Pro',
    searchName: 'iphone 15 pro',
    description: 'Brand new sealed',
    price: 2800000,
    currency: 'TZS',
    stock: 5,
    isActive: true,
    category: 'Electronics',
    subcategory: 'Phones',
    sellerId: 'uid-abc',
    sellerName: 'John Doe',
    sellerPhone: '+255712345678',
    location: 'Dar es Salaam',
    district: 'Kinondoni',
    brand: 'Apple',
    condition: 'new',
    barcode: '123456789',
    rating: 4.5,
    reviewCount: 12,
    viewCount: 100,
    soldCount: 3,
    isBoosted: true,
    boostedUntil: new Date('2026-10-01'),
    boostTier: 2,
    images: ['https://res.cloudinary.com/example/v1/img1.jpg', 'https://res.cloudinary.com/example/v1/img2.jpg'],
    imageMetadata: [],
    videoUrl: null,
    searchKeywords: ['iphone', 'apple', 'phone'],
    isWholesale: false,
    wholesaleTiers: [],
    variants: [{ label: '256GB', extra: 0 }],
    attributes: { color: 'black' },
    createdAt: new Date('2026-09-01T10:00:00Z'),
    ...overrides,
  };
}

describe('mapFirestoreProductToPrisma', () => {
  it('maps required fields correctly', () => {
    const doc = firestoreDoc();
    const result = mapFirestoreProductToPrisma(doc, { sellerProfileId: SELLER_ID, categoryId: CATEGORY_ID });

    assert.equal(result.title, 'iPhone 15 Pro');
    assert.equal(typeof result.slug, 'string');
    assert.ok(result.slug.startsWith('iphone-15-pro-'));
    assert.equal(result.price, BigInt(2800000));
    assert.equal(result.currency, 'TZS');
    assert.equal(result.stock, 5);
    assert.equal(result.status, 'published');
    assert.equal(result.condition, 'new');
    assert.equal(result.sellerId, undefined);
    assert.equal(result.categoryId, CATEGORY_ID);
    assert.equal(result.createdAt.getTime(), new Date('2026-09-01T10:00:00Z').getTime());
  });

  it('sets status to draft when isActive is false', () => {
    const result = mapFirestoreProductToPrisma(firestoreDoc({ isActive: false }), { sellerProfileId: SELLER_ID, categoryId: CATEGORY_ID });
    assert.equal(result.status, 'draft');
  });

  it('throws when name is empty', () => {
    assert.throws(() => mapFirestoreProductToPrisma(firestoreDoc({ name: '' }), { sellerProfileId: SELLER_ID, categoryId: CATEGORY_ID }), /name required/);
  });

  it('throws when price is non-positive', () => {
    assert.throws(() => mapFirestoreProductToPrisma(firestoreDoc({ price: 0 }), { sellerProfileId: SELLER_ID, categoryId: CATEGORY_ID }), /price/);
    assert.throws(() => mapFirestoreProductToPrisma(firestoreDoc({ price: -100 }), { sellerProfileId: SELLER_ID, categoryId: CATEGORY_ID }), /price/);
  });

  it('throws when sellerProfileId missing', () => {
    assert.throws(() => mapFirestoreProductToPrisma(firestoreDoc(), { sellerProfileId: null, categoryId: CATEGORY_ID }), /sellerProfileId/);
  });

  it('accepts null categoryId', () => {
    const result = mapFirestoreProductToPrisma(firestoreDoc(), { sellerProfileId: SELLER_ID, categoryId: null });
    assert.equal(result.categoryId, null);
  });

  it('rounds fractional prices to integer', () => {
    const result = mapFirestoreProductToPrisma(firestoreDoc({ price: 9999.7 }), { sellerProfileId: SELLER_ID, categoryId: CATEGORY_ID });
    assert.equal(result.price, BigInt(10000));
  });

  it('normalises unknown condition to new', () => {
    assert.equal(normaliseCondition('banana'), 'new');
    assert.equal(normaliseCondition('used_like_new'), 'used_like_new');
    assert.equal(normaliseCondition('Refurbished'), 'refurbished');
  });

  it('builds a valid slug from name', () => {
    const slug = buildSlug('Hello World!');
    assert.ok(slug.startsWith('hello-world-'));
    assert.ok(slug.length <= 68);
  });

  it('handles Firestore serverTimestamp (null)', () => {
    const result = mapFirestoreProductToPrisma(firestoreDoc({ createdAt: null }), { sellerProfileId: SELLER_ID, categoryId: CATEGORY_ID });
    assert.ok(result.createdAt instanceof Date);
  });

  it('handles Firestore Timestamp-like object', () => {
    const fakeTs = { toDate: () => new Date('2025-01-01T00:00:00Z') };
    const result = mapFirestoreProductToPrisma(firestoreDoc({ createdAt: fakeTs }), { sellerProfileId: SELLER_ID, categoryId: CATEGORY_ID });
    assert.equal(result.createdAt.getTime(), new Date('2025-01-01T00:00:00Z').getTime());
  });

  it('preserves all legacy fields in snapshot', () => {
    const result = mapFirestoreProductToPrisma(firestoreDoc(), { sellerProfileId: SELLER_ID, categoryId: CATEGORY_ID });
    assert.equal(result.snapshot.sellerName, 'John Doe');
    assert.equal(result.snapshot.sellerPhone, '+255712345678');
    assert.deepEqual(result.snapshot.images, firestoreDoc().images);
    assert.equal(result.snapshot.rating, 4.5);
    assert.equal(result.snapshot.brand, 'Apple');
    assert.equal(result.snapshot.isBoosted, true);
    assert.equal(result.snapshot.boostTier, 2);
    assert.deepEqual(result.snapshot.variants, [{ label: '256GB', extra: 0 }]);
    assert.equal(result.snapshot.searchKeywords.length, 3);
  });

  it('excludes fields not in LEGACY_KEYS from snapshot', () => {
    const result = mapFirestoreProductToPrisma(firestoreDoc({ randomField: 'nope' }), { sellerProfileId: SELLER_ID, categoryId: CATEGORY_ID });
    assert.equal(result.snapshot.randomField, undefined);
  });

  it('keeps category and subcategory in the snapshot', () => {
    const result = mapFirestoreProductToPrisma(
      firestoreDoc({ title: 'Chair', category: 'Home & Garden', subcategory: 'Furniture' }),
      { sellerProfileId: SELLER_ID, categoryId: CATEGORY_ID }
    );
    assert.equal(result.snapshot.category, 'Home & Garden');
    assert.equal(result.snapshot.subcategory, 'Furniture');
  });
});

describe('mapFirestoreMediaToProductRows', () => {
  it('maps Cloudinary images into ordered image rows', () => {
    const rows = mapFirestoreMediaToProductRows({
      images: ['https://res.cloudinary.com/a/img1.jpg', 'https://res.cloudinary.com/a/img2.jpg'],
    });
    assert.equal(rows.length, 2);
    assert.equal(rows[0].type, 'image');
    assert.equal(rows[0].r2Key, 'https://res.cloudinary.com/a/img1.jpg');
    assert.equal(rows[0].sortOrder, 0);
    assert.equal(rows[1].sortOrder, 1);
  });

  it('appends a video row after the images', () => {
    const rows = mapFirestoreMediaToProductRows({
      images: ['https://res.cloudinary.com/a/img1.jpg'],
      videoUrl: 'https://res.cloudinary.com/a/clip.mp4',
    });
    assert.equal(rows.length, 2);
    assert.equal(rows[1].type, 'video');
    assert.equal(rows[1].r2Key, 'https://res.cloudinary.com/a/clip.mp4');
    assert.equal(rows[1].sortOrder, 1);
  });

  it('skips non-http image entries and returns empty for no media', () => {
    assert.deepEqual(mapFirestoreMediaToProductRows({ images: ['relative.png', 42] }), []);
    assert.deepEqual(mapFirestoreMediaToProductRows({}), []);
    assert.deepEqual(mapFirestoreMediaToProductRows(null), []);
  });
});
