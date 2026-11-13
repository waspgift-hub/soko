// Hermetic tests for the AI tool registry. The database and external
// integrations are stubbed in require.cache, so the real registry's safety
// rules (whitelist, scoping, no-money) are exercised without any network or
// credentials.
const { describe, it, afterEach } = require('node:test');
const assert = require('node:assert/strict');

const DATABASE = require.resolve('../src/config/database');
const SEARCH_SERVICE = require.resolve('../src/modules/search/search-service');
const TAVILY = require.resolve('../src/modules/ai/tavily');
const REGISTRY = require.resolve('../src/modules/ai/tools/registry');

const CONTEXT = { uid: 'fb1', userId: 'usr-1', sellerProfileId: 'sp-1' };

function loadRegistry(storeMock) {
  require.cache[DATABASE] = {
    id: DATABASE, filename: DATABASE, loaded: true,
    exports: { getStore: () => storeMock },
  };
  require.cache[SEARCH_SERVICE] = {
    id: SEARCH_SERVICE, filename: SEARCH_SERVICE, loaded: true,
    exports: { searchProducts: async () => ({ products: [], pagination: {} }) },
  };
  require.cache[TAVILY] = {
    id: TAVILY, filename: TAVILY, loaded: true,
    exports: { searchWeb: async () => ({ results: [] }) },
  };
  delete require.cache[REGISTRY];
  return require(REGISTRY);
}

function storeWith({ userRow = null } = {}) {
  const calls = { profileUpdates: [], userSelects: [] };
  const store = {
    user: {
      findUnique: async ({ select } = {}) => {
        calls.userSelects.push(select || {});
        return userRow;
      },
    },
    sellerProfile: {
      update: async ({ where, data }) => {
        calls.profileUpdates.push({ where, data });
        return { id: where.id, ...data };
      },
    },
  };
  return { store, calls };
}

afterEach(() => {
  for (const k of [DATABASE, SEARCH_SERVICE, TAVILY, REGISTRY]) delete require.cache[k];
});

describe('ai tool safety (real registry)', () => {
  describe('update_my_store', () => {
    it('writes only whitelisted fields, scoped by the caller, not an arg', async () => {
      const { store, calls } = storeWith();
      const registry = loadRegistry(store);

      const out = await registry.invoke(
        'update_my_store',
        { storeName: '  Duka Bora  ', storeDescription: 'Bidhaa za uhakika' },
        CONTEXT,
      );

      assert.equal(out.success, true);
      assert.deepEqual(calls.profileUpdates[0].where, { id: 'sp-1' });
      assert.deepEqual(calls.profileUpdates[0].data, {
        storeName: 'Duka Bora',
        storeDescription: 'Bidhaa za uhakika',
      });
    });

    it('never persists a money key even when the model passes one', async () => {
      const { store, calls } = storeWith();
      const registry = loadRegistry(store);

      await registry.invoke(
        'update_my_store',
        { storeName: 'A', walletBalance: 99999, totalRevenue: 123, transferTo: 'x' },
        CONTEXT,
      );

      const data = calls.profileUpdates[0].data;
      assert.deepEqual(Object.keys(data), ['storeName']);
    });

    it('caps field lengths', async () => {
      const { store, calls } = storeWith();
      const registry = loadRegistry(store);

      await registry.invoke('update_my_store', { storeName: 'x'.repeat(150) }, CONTEXT);

      assert.equal(calls.profileUpdates[0].data.storeName.length, 100);
    });

    it('refuses an empty storeName', async () => {
      const registry = loadRegistry(storeWith().store);
      const out = await registry.invoke('update_my_store', { storeName: '   ' }, CONTEXT);
      assert.match(out.error, /storeName/);
    });

    it('returns a clear error when no updatable field is given', async () => {
      const registry = loadRegistry(storeWith().store);
      const out = await registry.invoke('update_my_store', { walletBalance: 1 }, CONTEXT);
      assert.match(out.error, /storeName, storeDescription/);
    });

    it('refuses to run without a seller profile', async () => {
      const registry = loadRegistry(storeWith().store);
      const out = await registry.invoke(
        'update_my_store',
        { storeName: 'A' },
        { uid: 'fb1', userId: 'usr-1', sellerProfileId: null },
      );
      assert.match(out.error, /Become a seller/);
    });
  });

  describe('get_my_profile', () => {
    it('never loads or returns balance fields', async () => {
      const userRow = {
        displayName: 'Asha', email: 'a@x.co', phone: '2557',
        accountStatus: 'active', kycStatus: 'verified', createdAt: new Date('2026-01-01'),
      };
      const { store, calls } = storeWith({ userRow });
      const registry = loadRegistry(store);

      const out = await registry.invoke('get_my_profile', {}, CONTEXT);

      assert.ok(!('wallet_balance' in out), 'wallet_balance leaked into profile');
      assert.ok(!('seller_balance' in out), 'seller_balance leaked into profile');
      const select = calls.userSelects[0];
      assert.ok(!('walletBalance' in select), 'select requested walletBalance');
      assert.ok(!('sellerBalance' in select), 'select requested sellerBalance');
    });
  });

  it('returns an error object for an unknown tool, never throws', async () => {
    const registry = loadRegistry(storeWith().store);
    const out = await registry.invoke('pay_someone', {}, CONTEXT);
    assert.match(out.error, /No such tool/);
  });
});