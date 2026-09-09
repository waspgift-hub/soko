const test = require('node:test');
const assert = require('node:assert/strict');

const { validateDisputeSplit } = require('../src/modules/disputes/dispute-service');

test('valid split that covers the escrow exactly is accepted', () => {
  assert.deepEqual(validateDisputeSplit(50000n, 20000, 30000), {
    buyerAmount: '20000',
    sellerAmount: '30000',
  });
});

test('split with zero buyer share is rejected (no free money to seller)', () => {
  assert.throws(() => validateDisputeSplit(50000n, 0, 50000));
});

test('split exceeding the escrow is rejected', () => {
  assert.throws(() => validateDisputeSplit(50000n, 40000, 20000));
});

test('split that leaves leftover money is rejected', () => {
  assert.throws(() => validateDisputeSplit(50000n, 10000, 10000));
});

test('missing split amounts are rejected', () => {
  assert.throws(() => validateDisputeSplit(50000n, null, 30000));
  assert.throws(() => validateDisputeSplit(50000n, 20000, undefined));
});

test('string and number representations of amounts are both valid', () => {
  assert.deepEqual(validateDisputeSplit(50000n, '25000', '25000'), {
    buyerAmount: '25000',
    sellerAmount: '25000',
  });
});