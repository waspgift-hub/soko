// The admin panel's commission field has to be the live control: an owner who
// saves 5% expects the next order to charge 5%, without a deploy. These tests
// pin the precedence chain and, just as importantly, the fallback: no stored
// document (or a Firestore outage) must keep the env default instead of
// silently switching the platform to the built-in 3.5% or to zero.
const { test, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');

const SETTINGS = require.resolve('../src/modules/admin/settings-service');
const PARITY = require.resolve('../src/utils/commission-parity');

const realSettings = require(SETTINGS);

function loadParityWith(stored) {
  require.cache[SETTINGS] = {
    id: SETTINGS,
    filename: SETTINGS,
    loaded: true,
    exports: {
      ...realSettings,
      getStoredSettings: async () => {
        if (stored instanceof Error) throw stored;
        return stored;
      },
    },
  };
  delete require.cache[PARITY];
  return require(PARITY);
}

beforeEach(() => {
  delete require.cache[PARITY];
});

afterEach(() => {
  delete require.cache[PARITY];
  delete require.cache[SETTINGS];
});

test('the saved admin percentage overrides the env default', async () => {
  const parity = loadParityWith({ paymentsAndCurrency: { platformCommissionPct: 5 } });
  const rate = await parity.resolvePlatformRate();

  assert.equal(rate, 0.05);
  assert.equal(parity.computeSellerParity(100000n, 0n, rate).commission, 5000n);
  assert.equal(parity.computeSellerParity(100000n, 0n, rate).totalAmount, 105000n);
});

test('an admin value stored as a fraction is accepted unchanged', async () => {
  const parity = loadParityWith({ paymentsAndCurrency: { platformCommissionPct: 0.02 } });
  assert.equal(await parity.resolvePlatformRate(), 0.02);
});

test('a saved zero is honoured instead of falling through to the env rate', async () => {
  const parity = loadParityWith({ paymentsAndCurrency: { platformCommissionPct: 0 } });
  const rate = await parity.resolvePlatformRate();

  assert.equal(rate, 0);
  assert.equal(parity.computeSellerParity(100000n, 0n, rate).commission, 0n);
});

test('no stored document keeps the env default', async () => {
  const parity = loadParityWith(null);
  assert.equal(await parity.resolvePlatformRate(), parity.platformRate());
});

test('a stored document without the field keeps the env default', async () => {
  const parity = loadParityWith({ paymentsAndCurrency: { currency: 'TZS' } });
  assert.equal(await parity.resolvePlatformRate(), parity.platformRate());
});

test('a Firestore failure keeps the env default', async () => {
  const parity = loadParityWith(new Error('unavailable'));
  assert.equal(await parity.resolvePlatformRate(), parity.platformRate());
});

test('the resolved rate is cached briefly and the settings read is not repeated', async () => {
  let reads = 0;
  const parity = loadParityWith(null);
  require.cache[SETTINGS].exports.getStoredSettings = async () => {
    reads += 1;
    return { paymentsAndCurrency: { platformCommissionPct: 4 } };
  };

  assert.equal(await parity.resolvePlatformRate(), 0.04);
  assert.equal(await parity.resolvePlatformRate(), 0.04);
  assert.equal(reads, 1);
});
