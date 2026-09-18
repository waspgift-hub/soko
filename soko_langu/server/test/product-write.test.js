const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { applySnapshotPatch } = require('../src/modules/products/product-service');

describe('applySnapshotPatch', () => {
  it('starts from the existing snapshot when present', () => {
    const merged = applySnapshotPatch(
      { brand: 'Bmw', rating: 4.5, legacyId: 'opaque-doc' },
      { }
    );
    assert.equal(merged.brand, 'Bmw');
    assert.equal(merged.rating, 4.5);
    assert.equal(merged.legacyId, 'opaque-doc');
  });

  it('copies every legacy-only field the seller hub sends', () => {
    const data = {
      category: 'Vehicles',
      subcategory: 'All Cars',
      brand: 'Bmw',
      location: 'Dar es Salaam',
      district: 'Kinondoni',
      barcode: '890123',
      isWholesale: true,
      wholesaleTiers: [{ minQuantity: 5, pricePerUnit: 4000000 }],
      variants: [{ name: 'Color', value: 'Blue', stock: 1 }],
      attributes: { drive: 'MT' },
      images: ['https://res.cloudinary.com/x/image/upload/v1/a.jpg'],
      imageMetadata: [{ url: 'https://res.cloudinary.com/x/image/upload/v1/a.jpg', width: 800 }],
      videoUrl: 'https://res.cloudinary.com/x/video/v1/v.mp4',
      searchKeywords: ['bmw', 'm4'],
    };
    const merged = applySnapshotPatch({}, data);
    assert.deepEqual(merged, { ...data });
  });

  it('does not copy traffic-light columns into the snapshot', () => {
    const merged = applySnapshotPatch({}, { title: 'Ignored', price: 5, status: 'draft' });
    assert.equal(merged.title, undefined);
    assert.equal(merged.price, undefined);
    assert.equal(merged.status, undefined);
  });

  it('never mutates the stored snapshot object', () => {
    const base = Object.freeze({ brand: 'A' });
    const merged = applySnapshotPatch(base, { brand: 'B' });
    assert.equal(base.brand, 'A');
    assert.equal(merged.brand, 'B');
  });
});