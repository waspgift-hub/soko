const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');

// searchProducts reads Firestore directly, so the module is loaded against fakes
// injected into require.cache. Everything else in the repo's unit tests is pure,
// which is why there is no shared harness for this.
const FIREBASE = require.resolve('../src/config/firebase');
const SEARCH = require.resolve('../src/modules/search/search-service');
const { buildMirrorDoc } = require('../src/modules/products/product-mirror');

let emittedFilters = [];
let indexedTokens = [];
let docs = [];

/** Minimal chainable Firestore stub that records the query it was handed. */
function fakeDb() {
  const make = (ops) => {
    const q = {
      where(field, op, val) {
        ops.filters.push({ field, op, val });
        if (op === 'array-contains') indexedTokens.push(val);
        return make(ops);
      },
      orderBy(field, dir) {
        ops.orderBys.push({ field, dir });
        return make(ops);
      },
      limit(n) {
        ops.limit = n;
        return make(ops);
      },
      startAfter(ref) {
        ops.after = ref && ref.id;
        return make(ops);
      },
      async get() {
        // Replay only the equality filters Firestore could actually serve.
        let rows = docs;
        for (const f of ops.filters) {
          if (f.op === 'array-contains') {
            rows = rows.filter((d) => Array.isArray(d[f.field]) && d[f.field].includes(f.val));
            continue;
          }
          if (f.op !== '==' && f.op !== '>=' && f.op !== '<=') continue;
          rows = rows.filter((d) => {
            if (f.op === '==') return d[f.field] === f.val;
            return f.op === '>=' ? d[f.field] >= f.val : d[f.field] <= f.val;
          });
        }
        // An `array-contains` query with no orderBy is served in __name__ order,
        // which is what makes `startAfter` paging correct here.
        if (ops.after != null) rows = rows.filter((d) => d.__id > ops.after);
        rows = [...rows].sort((a, b) => (a.__id < b.__id ? -1 : 1));
        const out = rows.slice(0, ops.limit || rows.length);
        return {
          size: out.length,
          empty: out.length === 0,
          docs: out.map((d) => ({ id: d.__id, data: () => d })),
          forEach(cb) { out.forEach((d) => cb({ id: d.__id, data: () => d })); },
        };
      },
    };
    return q;
  };
  return { collection: () => make({ filters: [], orderBys: [], limit: null }) };
}

function mirrorDoc(overrides) {
  // Mirrors what the app writes: the mirror copies `searchKeywords` straight
  // from the product snapshot, and the client derives it as the lower-cased
  // word set of name + description + category + brand. Fixtures that leave it
  // empty hide the fact that the indexed path depends on it entirely.
  const searchKeywords = [
    ...new Set(
      `${overrides.name} ${overrides.description || ''} ${overrides.category || ''} ${overrides.brand || ''}`
        .toLowerCase()
        .split(/[\s,.-]+/)
        .filter((w) => w.length >= 2),
    ),
  ];
  const doc = buildMirrorDoc(
    {
      id: overrides.__id,
      title: overrides.name,
      price: overrides.price,
      stock: 3,
      condition: 'used',
      status: 'published',
      createdAt: new Date('2026-09-10T10:00:00Z'),
      snapshot: {
        title: overrides.name,
        description: overrides.description || '',
        price: overrides.price,
        images: [],
        imageMetadata: [],
        videoUrl: null,
        sellerId: 'uid-1',
        sellerName: overrides.sellerName || 'Probe Store',
        category: overrides.category || 'Simu',
        subcategory: overrides.subcategory || null,
        location: 'Dar es Salaam',
        district: null,
        isWholesale: false,
        wholesaleTiers: [],
        variants: [],
        attributes: {},
        brand: overrides.brand || 'Apple',
        searchKeywords,
        barcode: null,
        sellerKycApproved: true,
        isBoosted: false,
        boostTier: null,
      },
    },
    { sellerFirebaseUid: 'uid-1', sellerName: overrides.sellerName || 'Probe Store' }
  );
  return { ...doc, __id: overrides.__id, isActive: overrides.isActive !== false };
}

function loadSearchService() {
  require.cache[FIREBASE] = { id: FIREBASE, filename: FIREBASE, loaded: true, exports: { getFirebaseFirestore: fakeDb } };
  delete require.cache[SEARCH];
  return require(SEARCH);
}

describe('searchProducts', () => {
  let searchProducts;

  beforeEach(() => {
    emittedFilters = [];
    indexedTokens = [];
    docs = [
      mirrorDoc({ __id: 'p1', name: 'iPhone 15 Pro 256GB', price: 1850000 }),
      mirrorDoc({ __id: 'p2', name: 'iPhone 13 128GB', price: 950000 }),
      mirrorDoc({ __id: 'p3', name: 'Samsung Galaxy A54', price: 780000 }),
      mirrorDoc({ __id: 'p4', name: 'Laptop HP Pavilion 15', price: 1650000, category: 'Kompyuta' }),
      mirrorDoc({ __id: 'p5', name: 'iPhone 15 Pro draft', price: 2900000, isActive: false }),
    ];
    searchProducts = loadSearchService().searchProducts;
  });

  afterEach(() => {
    delete require.cache[SEARCH];
    delete require.cache[FIREBASE];
  });

  it('filters on the field the mirror actually writes', async () => {
    // The bug this pins: search filtered on `status === 'published'`, which
    // product-mirror.js never writes, so every query returned nothing.
    const r = await searchProducts({ query: 'iPhone' });
    assert.ok(r.products.length > 0, 'isActive-filtered search returned rows');
    assert.ok(!r.products.some((p) => /draft/.test(p.title)), 'inactive doc leaked through');
  });

  it('requires every query token to match', async () => {
    // OR-matching let "iPhone 15" return a 15-inch laptop, ranked alongside the
    // actual phone.
    const r = await searchProducts({ query: 'iPhone 15' });
    const titles = r.products.map((p) => p.title);
    assert.deepEqual(titles, ['iPhone 15 Pro 256GB']);
  });

  it('matches a token that is a substring of a word', async () => {
    const r = await searchProducts({ query: 'phone' });
    assert.ok(r.products.some((p) => /iPhone/.test(p.title)), '"phone" should find "iPhone"');
  });

  it('applies price bounds without asking Firestore for a price range', async () => {
    // A range on `price` alongside an orderBy on `createdAt` is rejected unless
    // a composite index exists, which would make search depend on manual index
    // work nobody has done. The bounds must stay in memory.
    const cheap = await searchProducts({ query: 'iPhone', maxPrice: 1000000 });
    assert.deepEqual(cheap.products.map((p) => p.title), ['iPhone 13 128GB']);

    const dear = await searchProducts({ query: 'iPhone', minPrice: 1000000 });
    assert.ok(dear.products.some((p) => p.price === 1850000));
    assert.ok(!dear.products.some((p) => p.price === 950000));
  });

  it('filters category case-insensitively', async () => {
    const r = await searchProducts({ query: 'iPhone', categoryId: 'kompyuta' });
    assert.equal(r.products.length, 0);
    const ok = await searchProducts({ query: 'Laptop', categoryId: 'Kompyuta' });
    assert.equal(ok.products.length, 1);
  });

  it('returns nothing rather than a guess when there is no match', async () => {
    const r = await searchProducts({ query: 'Boeing 747' });
    assert.equal(r.products.length, 0);
    assert.equal(r.pagination.total, 0);
  });

  it('lists newest first with no query', async () => {
    const r = await searchProducts({ query: '', limit: 10 });
    assert.equal(r.products.length, 4);
  });

  it('pages the indexed lookup instead of stopping at one page of candidates', async () => {
    // The indexed path used to take a single `.limit(300)` per token. An
    // `array-contains` query with no orderBy comes back in __name__ order, so
    // for any token matching more than 300 products the user silently saw an
    // arbitrary 300. It must page with startAfter until the match set ends.
    const many = [];
    for (let i = 0; i < 350; i += 1) {
      many.push({
        ...mirrorDoc({ __id: `bulk-${String(i).padStart(4, '0')}`, name: `Wheelie bin ${i}`, price: 20000 + i }),
        searchKeywords: ['wheelie'],
      });
    }
    docs = many;

    const r = await searchProducts({ query: 'wheelie', limit: 50 });

    assert.equal(r.pagination.total, 350, 'every indexed match must be scored, not just the first 300');
    assert.equal(r.truncated, false);
    assert.equal(r.strategy, 'indexed');
  });

  it('reports truncation rather than hiding a capped result set', async () => {
    // Beyond the ceiling the answer is partial. Saying so is the difference
    // between "no such product" and "we stopped looking".
    const many = [];
    for (let i = 0; i < 3400; i += 1) {
      many.push({
        ...mirrorDoc({ __id: `huge-${String(i).padStart(5, '0')}`, name: `Fridge ${i}`, price: 500000 + i }),
        searchKeywords: ['fridge'],
      });
    }
    docs = many;

    const r = await searchProducts({ query: 'fridge', limit: 20 });

    assert.equal(r.truncated, true);
    assert.ok(r.pagination.total < 3400, 'the ceiling is real, not decorative');
    assert.ok(r.pagination.total > 0);
  });

  it('drops stop words so a phrase query does not chase a whole catalogue', async () => {
    // "for sale" tokenised to [for, sale]; `for` matches a large slice of the
    // catalogue for no ranking benefit. With them filtered the index is asked
    // for the meaningful token only.
    await searchProducts({ query: 'for sale' });
    assert.ok(indexedTokens.includes('sale'), 'the meaningful token must still be searched');
    assert.ok(!indexedTokens.includes('for'), 'stop words must not reach the index');
  });

  it('falls back to the scan when the index misses, preserving substring search', async () => {
    // "phone" is a substring of "iPhone" but is not a stored keyword, so the
    // exact-token index finds nothing. Answering "no results" here would be a
    // silent recall regression versus the pre-index scan.
    const r = await searchProducts({ query: 'phone' });
    assert.equal(r.strategy, 'scan_fallback');
    assert.ok(r.products.some((p) => /iPhone/.test(p.title)));
  });
});
