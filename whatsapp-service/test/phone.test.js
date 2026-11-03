const test = require('node:test');
const assert = require('node:assert/strict');
const { normalizePhone, maskPhone } = require('../src/phone');
const { validateMessage, runPool } = require('../src/app');

test('normalizes common Tanzanian formats to 255 + digits', () => {
  assert.equal(normalizePhone('+255693273241', '255'), '255693273241');
  assert.equal(normalizePhone('255693273241', '255'), '255693273241');
  assert.equal(normalizePhone('0693273241', '255'), '255693273241');
  assert.equal(normalizePhone('693273241', '255'), '255693273241');
  assert.equal(normalizePhone('+255 693 273 241', '255'), '255693273241');
  assert.equal(normalizePhone('00255693273241', '255'), '255693273241');
});

test('rejects malformed numbers', () => {
  assert.equal(normalizePhone('abc', '255'), null);
  assert.equal(normalizePhone('12', '255'), null);
  assert.equal(normalizePhone('1234567890123456', '255'), null);
  assert.equal(normalizePhone('', '255'), null);
  assert.equal(normalizePhone(null, '255'), null);
});

test('masks all but the last four digits', () => {
  assert.equal(maskPhone('255693273241'), '********3241');
  assert.equal(maskPhone('12'), '****');
});

test('validates message bodies', () => {
  assert.equal(validateMessage('hello'), null);
  assert.ok(validateMessage('   '));
  assert.ok(validateMessage(42));
  assert.ok(validateMessage('x'.repeat(4097)));
});

test('runPool never exceeds the concurrency limit', async () => {
  let active = 0;
  let peak = 0;
  const results = await runPool([1, 2, 3, 4, 5, 6, 7], 3, async (n) => {
    active += 1;
    peak = Math.max(peak, active);
    await new Promise((r) => setTimeout(r, 5));
    active -= 1;
    return n * 2;
  });
  assert.equal(peak, 3);
  assert.deepEqual(results, [2, 4, 6, 8, 10, 12, 14]);
});
