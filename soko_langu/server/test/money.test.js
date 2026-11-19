const test = require('node:test');
const assert = require('node:assert/strict');

const {
  isFlashSaleStillActive,
  resolveEffectivePrice,
  calcMnoCheckoutFee,
  buildPricingBreakdown,
  MNO_CHECKOUT_FEE_TIERS,
} = require('../money');
const { calcGatewayFee } = require('../azampay');

// ---------------------------------------------------------------------------
// Flash sale price resolution
// ---------------------------------------------------------------------------

function mockSnap(docs) {
  return {
    empty: docs.length === 0,
    docs: docs.map((d) => ({ data: () => d })),
  };
}

function mockDb(flashSales) {
  return {
    collection: () => {
      let filters = [];
      const chain = {
        where: (field, op, value) => {
          filters.push({ field, op, value });
          return chain;
        },
        limit: () => ({ get: async () => mockSnap(applyFilters(flashSales, filters)) }),
        get: async () => mockSnap(applyFilters(flashSales, filters)),
      };
      return chain;
    },
  };
}

// Emulate Firestore where() semantics for the filters the money code uses.
function applyFilters(docs, filters) {
  return docs.filter((d) =>
    filters.every(({ field, op, value }) => {
      if (op === '==') return d[field] === value;
      return true;
    }),
  );
}

test('resolveEffectivePrice uses salePrice when active flash sale exists', async () => {
  const now = Date.now();
  const db = mockDb([
    { productId: 'p1', salePrice: 47500, originalPrice: 50000, endTime: new Date(now + 86400000), isActive: true },
  ]);
  // Client sends stale full price; server must return the discounted price.
  const price = await resolveEffectivePrice(db, 'p1', 50000);
  assert.equal(price, 47500);
});

test('resolveEffectivePrice ignores expired flash sale and keeps client price', async () => {
  const now = Date.now();
  const db = mockDb([
    { productId: 'p1', salePrice: 47500, originalPrice: 50000, endTime: new Date(now - 86400000), isActive: true },
  ]);
  const price = await resolveEffectivePrice(db, 'p1', 50000);
  assert.equal(price, 50000);
});

test('resolveEffectivePrice keeps client price when no flash sale exists', async () => {
  const db = mockDb([]);
  const price = await resolveEffectivePrice(db, 'p1', 50000);
  assert.equal(price, 50000);
});

test('resolveEffectivePrice ignores inactive flash sale', async () => {
  const now = Date.now();
  const db = mockDb([
    { productId: 'p1', salePrice: 47500, endTime: new Date(now + 86400000), isActive: false },
  ]);
  const price = await resolveEffectivePrice(db, 'p1', 50000);
  assert.equal(price, 50000);
});

test('resolveEffectivePrice ignores zero salePrice', async () => {
  const now = Date.now();
  const db = mockDb([
    { productId: 'p1', salePrice: 0, endTime: new Date(now + 86400000), isActive: true },
  ]);
  const price = await resolveEffectivePrice(db, 'p1', 50000);
  assert.equal(price, 50000);
});

test('resolveEffectivePrice rounds salePrice', async () => {
  const now = Date.now();
  const db = mockDb([
    { productId: 'p1', salePrice: 47500.6, endTime: new Date(now + 86400000), isActive: true },
  ]);
  const price = await resolveEffectivePrice(db, 'p1', 50000);
  assert.equal(price, 47501);
});

test('resolveEffectivePrice falls back to client price when db throws', async () => {
  const db = { collection: () => { throw new Error('boom'); } };
  const price = await resolveEffectivePrice(db, 'p1', 50000);
  assert.equal(price, 50000);
});

// ---------------------------------------------------------------------------
// isFlashSaleStillActive — time-window logic
// ---------------------------------------------------------------------------

test('isFlashSaleStillActive true when endTime is in the future', () => {
  const now = new Date('2026-08-14T12:00:00Z');
  assert.equal(isFlashSaleStillActive({ endTime: new Date('2026-08-15T12:00:00Z') }, now), true);
});

test('isFlashSaleStillActive false when endTime is in the past', () => {
  const now = new Date('2026-08-14T12:00:00Z');
  assert.equal(isFlashSaleStillActive({ endTime: new Date('2026-08-13T12:00:00Z') }, now), false);
});

test('isFlashSaleStillActive parses Firestore-like _seconds', () => {
  const now = new Date('2026-08-14T12:00:00Z');
  const endSeconds = Math.floor(new Date('2026-08-15T12:00:00Z').getTime() / 1000);
  assert.equal(isFlashSaleStillActive({ endTime: { _seconds: endSeconds } }, now), true);
});

test('isFlashSaleStillActive returns false for missing endTime', () => {
  assert.equal(isFlashSaleStillActive({}, new Date()), false);
});

// ---------------------------------------------------------------------------
// Gateway fees (calcGatewayFee)
// ---------------------------------------------------------------------------

test('calcGatewayFee: wallet is free', () => {
  assert.equal(calcGatewayFee('wallet', 50000), 0);
});

test('calcGatewayFee: USSD Push fee is tiered', () => {
  assert.equal(calcGatewayFee('ussd_push', 500), 54);
  assert.equal(calcGatewayFee('ussd_push', 3000), 230);
  assert.equal(calcGatewayFee('ussd_push', 100000), 3240);
});

test('calcGatewayFee: billpay default is 1%', () => {
  assert.equal(calcGatewayFee('billpay', 100000), 1000);
});

test('calcGatewayFee: halopesa billpay is 2%', () => {
  assert.equal(calcGatewayFee('billpay', 100000, 'halopesa'), 2000);
});

test('calcGatewayFee: crdb billpay is 1%', () => {
  assert.equal(calcGatewayFee('billpay', 100000, 'crdb'), 1000);
  assert.equal(calcGatewayFee('billpay', 100000, 'crdb_billpay'), 1000);
});

test('calcGatewayFee: crdb direct debit is flat 2000', () => {
  assert.equal(calcGatewayFee('crdb_direct_debit', 100000), 2000);
});

test('calcGatewayFee: unknown provider falls back to standard 1%', () => {
  assert.equal(calcGatewayFee('billpay', 100000, 'unknown_provider'), 1000);
});

test('calcGatewayFee: unknown method falls back to USSD fee', () => {
  assert.equal(calcGatewayFee('weird_method', 500), 54);
});

// ---------------------------------------------------------------------------
// MNO checkout fee + authoritative pricing breakdown
// ---------------------------------------------------------------------------

test('calcMnoCheckoutFee rejects non-finite and sub-tier amounts', () => {
  assert.equal(calcMnoCheckoutFee(NaN), 0);
  assert.equal(calcMnoCheckoutFee(Infinity), 0);
  assert.equal(calcMnoCheckoutFee(-100), 0);
  assert.equal(calcMnoCheckoutFee(499), 0);
});

test('calcMnoCheckoutFee covers every published tier and the ceiling', () => {
  for (const [min, max, fee] of MNO_CHECKOUT_FEE_TIERS) {
    assert.equal(calcMnoCheckoutFee(min), fee, `min ${min}`);
    assert.equal(calcMnoCheckoutFee(max), fee, `max ${max}`);
  }
  assert.equal(calcMnoCheckoutFee(3000001), 7960);
});

test('buildPricingBreakdown keeps the provider fee out of escrow', () => {
  const p = buildPricingBreakdown({
    productPrice: 500,
    commission: 0,
    at: new Date('2026-01-01T00:00:00Z'),
  });

  assert.equal(p.gatewayAmount, 500);
  assert.equal(p.processingFee, 54);
  assert.equal(p.buyerTotal, 554);
  assert.equal(p.sellerNet, 500);
  assert.equal(p.processingFeePayer, 'buyer');
  assert.equal(p.currency, 'TZS');
});

test('buildPricingBreakdown treats free delivery as zero shipping', () => {
  const p = buildPricingBreakdown({
    productPrice: 50000,
    shippingFee: 0,
    commission: 1750,
  });

  assert.equal(p.shippingCost, 0);
  assert.equal(p.gatewayAmount, 51750);
  assert.equal(p.processingFee, 2136);
  assert.equal(p.buyerTotal, 53886);
  assert.equal(p.sellerNet, 50000);
});

test('buildPricingBreakdown never emits negative money', () => {
  const p = buildPricingBreakdown({
    productPrice: -500,
    shippingFee: -100,
    commission: -50,
  });

  assert.equal(p.productPrice, 0);
  assert.equal(p.shippingCost, 0);
  assert.equal(p.commission, 0);
  assert.equal(p.gatewayAmount, 0);
  assert.equal(p.buyerTotal, 0);
  assert.equal(p.sellerNet, 0);
});
