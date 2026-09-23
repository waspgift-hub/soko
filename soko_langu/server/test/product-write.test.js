const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { applySnapshotPatch, serializeProduct } = require('../src/modules/products/product-service');
const { applyListingPatch, listingPseudoRow } = require('../src/modules/products/product-store');

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

describe('serializeProduct', () => {
  it('flattens sellerId (Firebase UID) and sellerPhone from the seller relation', () => {
    const out = serializeProduct({
      id: 'p1',
      title: 'X',
      price: 5n,
      seller: {
        id: 'prof-1',
        storeName: 'Duka',
        storeSlug: 'duka',
        user: { firebaseUid: 'firebase-uid-9', phone: '+255700000000' },
      },
    });
    assert.equal(out.seller.sellerId, 'firebase-uid-9');
    assert.equal(out.seller.sellerPhone, '+255700000000');
    assert.equal(out.seller.storeName, 'Duka');
    assert.equal(out.price, 5n);
  });

  it('passes products without a seller relation through unchanged', () => {
    const row = { id: 'p2', price: 5n, snapshot: {} };
    assert.equal(serializeProduct(row), row);
  });
});

describe('applyListingPatch (Firestore-first doc patch)', () => {
  it('maps title/price/stock/condition to the doc schema', () => {
    const patched = applyListingPatch(
      { name: 'A', searchName: 'a' },
      { title: 'Bmw M4', price: 30000000, stock: 2, condition: 'used_like_new' }
    );
    assert.equal(patched.name, 'Bmw M4');
    assert.equal(patched.searchName, 'bmw m4');
    assert.equal(patched.price, 30000000);
    assert.equal(patched.stock, 2);
    assert.equal(patched.condition, 'used_like_new');
  });

  it('keeps the flattened legacy keys the app reads', () => {
    const doc = { name: 'X', images: [], brand: 'OldBrand' };
    const patched = applyListingPatch(doc, { brand: 'Bmw', imageMetadata: [{ url: 'u' }], variants: [] });
    assert.equal(patched.brand, 'Bmw');
    assert.deepEqual(patched.imageMetadata, [{ url: 'u' }]);
    assert.deepEqual(patched.variants, []);
    assert.equal(patched.images.length, 0);
  });

  it('touches updatedAt on every patch', () => {
    assert.ok(applyListingPatch({}, {}).updatedAt);
  });
});

describe('listingPseudoRow', () => {
  it('supplies the row fields buildMirrorDoc needs', () => {
    const row = listingPseudoRow({
      id: 'abc', data: { title: 'A', price: 5000 }, category: 'Vehicles', status: 'draft', createdAt: new Date('2026-09-01'),
    });
    assert.equal(row.id, 'abc');
    assert.equal(row.price, 5000);
    assert.equal(row.snapshot.category, 'Vehicles');
    assert.equal(row.status, 'draft');
  });
});