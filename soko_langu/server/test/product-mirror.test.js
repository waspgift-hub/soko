const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { buildMirrorDoc } = require('../src/modules/products/product-mirror');

function makeProduct(overrides = {}) {
  return {
    id: '1b9d6bcd-bbfd-4b2d-9b5d-ab8dfbbd4beb',
    title: 'Mirror Test',
    price: 25000,
    stock: 3,
    condition: 'used',
    status: 'published',
    createdAt: new Date('2026-09-10T10:00:00Z'),
    snapshot: {
      title: 'Mirror Test',
      description: 'a legacy-shaped listing',
      price: 25000,
      images: ['https://res.cloudinary.com/x/a.jpg'],
      imageMetadata: [],
      videoUrl: null,
      sellerId: 'legacy-firebase-uid',
      sellerName: 'Probe Store',
      category: 'Vehicles',
      subcategory: 'All Cars',
      location: 'Dar es Salaam',
      district: 'Kinondoni',
      isWholesale: true,
      wholesaleTiers: [{ minQuantity: 5, pricePerUnit: 23000 }],
      variants: [{ id: 'v1', name: 'Color', value: 'Red', stock: 1 }],
      attributes: { drive: 'AWD' },
      brand: 'ProbeBrand',
      searchKeywords: ['mirror'],
      barcode: '9090',
      sellerKycApproved: true,
      isBoosted: true,
      boostTier: 'gold',
    },
    ...overrides,
  };
}

describe('buildMirrorDoc', () => {
  it('projects the legacy Firestore shape from a Postgres row', () => {
    const doc = buildMirrorDoc(makeProduct(), {
      sellerFirebaseUid: 'firebase-uid-2',
      sellerName: 'Probe Store',
    });
    assert.equal(doc.legacyId, '1b9d6bcd-bbfd-4b2d-9b5d-ab8dfbbd4beb');
    assert.equal(doc.name, 'Mirror Test');
    assert.equal(doc.searchName, 'mirror test');
    assert.equal(doc.price, 25000);
    assert.equal(doc.sellerId, 'firebase-uid-2');
    assert.equal(doc.sellerName, 'Probe Store');
    assert.equal(doc.category, 'Vehicles');
    assert.equal(doc.brand, 'ProbeBrand');
    assert.equal(doc.isActive, true);
    assert.equal(doc.isBoosted, true);
    assert.equal(doc.boostTier, 'gold');
    assert.deepEqual(doc.variants.length, 1);
    assert.equal(doc.createdAt, '2026-09-10T10:00:00.000Z');
  });

  it('flips isActive for drafts and non-published statuses', () => {
    assert.equal(buildMirrorDoc(makeProduct({ status: 'draft' })).isActive, false);
    assert.equal(buildMirrorDoc(makeProduct({ status: 'rejected' })).isActive, false);
  });

  it('falls back to snapshot seller fields when no context is given', () => {
    const doc = buildMirrorDoc(makeProduct(), {});
    assert.equal(doc.sellerId, 'legacy-firebase-uid');
    assert.equal(doc.sellerName, 'Probe Store');
  });

  it('handles a bare migration row with minimal snapshot', () => {
    const doc = buildMirrorDoc({
      id: 'bare-id',
      title: 'Bare',
      price: 100,
      stock: 1,
      condition: 'new',
      status: 'published',
      createdAt: new Date('2026-09-01T00:00:00Z'),
      snapshot: {},
    });
    assert.equal(doc.name, 'Bare');
    assert.equal(doc.images.length, 0);
    assert.equal(doc.rating, 0);
    assert.equal(doc.category, null);
  });
});