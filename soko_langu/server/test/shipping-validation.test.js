const { test } = require('node:test');
const assert = require('node:assert');
const { validateShippingQuote, estimateDistanceTier } = require('../src/modules/shipping/shipping-validation');

test('cross-regional NORMAL quote within baseline', () => {
  const result = validateShippingQuote({
    amount: 20000,
    shippingAddress: { region: 'Dar es Salaam', city: 'Dar es Salaam' },
    sellerRegion: 'Arusha',
  });
  assert.strictEqual(result.verdict, 'NORMAL');
});

test('inflated quote triggers REVIEW_REQUIRED', () => {
  const result = validateShippingQuote({
    amount: 1000000, // TZS 1M — wildly above any baseline
    shippingAddress: { region: 'Dar es Salaam', city: 'Dar es Salaam' },
    sellerRegion: 'Dar es Salaam',
  });
  assert.strictEqual(result.verdict, 'REVIEW_REQUIRED');
});

test('unusually low quote triggers review', () => {
  const result = validateShippingQuote({
    amount: 100, // far below intra-city min
    shippingAddress: { region: 'Dar es Salaam', city: 'Dar es Salaam' },
    sellerRegion: 'Dar es Salaam',
  });
  assert.strictEqual(result.verdict, 'REVIEW_REQUIRED');
});

test('high-risk seller quote is reviewed', () => {
  const result = validateShippingQuote({
    amount: 5000,
    shippingAddress: { region: 'Dar es Salaam', city: 'Mbeya' },
    sellerRegion: 'Mbeya',
    sellerRiskScore: 80,
  });
  assert.strictEqual(result.verdict, 'REVIEW_REQUIRED');
});

test('extreme-risk seller with inflated quote is BLOCKED', () => {
  const result = validateShippingQuote({
    amount: 2000000,
    shippingAddress: { region: 'Dar es Salaam' },
    sellerRegion: 'Dar es Salaam',
    sellerRiskScore: 95,
  });
  assert.strictEqual(result.verdict, 'BLOCKED');
});

test('estimateDistanceTier assigns intra-city for same city', () => {
  const tier = estimateDistanceTier(
    { region: 'Dar es Salaam', city: 'Dar es Salaam' },
    'Dar es Salaam'
  );
  assert.strictEqual(tier, 'intra_city');
});
