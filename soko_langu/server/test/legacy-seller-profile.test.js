// Hermetic tests for legacy-seller recovery: sellers whose products predate
// the sellerProfiles requirement have no profile doc, so ownership checks and
// "My Ads" listing 404'd. The store is stubbed in require.cache so the real
// provisioning and dual-identity ownership logic runs without any network.
const { describe, it, afterEach } = require('node:test');
const assert = require('node:assert/strict');

const DATABASE = require.resolve('../src/config/database');
const SERVICE = require.resolve('../src/modules/products/product-service');

const UID = 'firebaseUidLegacy1';
const UUID_ID = '22222222-2222-4222-8222-222222222222';
const PROFILE_ID = '11111111-1111-4111-8111-111111111111';

function sellerProductsMock(rows) {
  return {
    findFirst: async ({ where, select }) => {
      const sellerIds = where?.OR
        ? where.OR.map((part) => part.sellerId)
        : [where?.sellerId];
      let match = rows.find((r) => sellerIds.includes(r.sellerId) && !r.deletedAt);
      if (!match) return null;
      if (select) {
        const out = {};
        for (const k of Object.keys(select)) out[k] = match[k];
        return out;
      }
      return match;
    },
    findMany: async ({ where }) => {
      const sellerIds = where?.OR
        ? where.OR.map((part) => part.sellerId)
        : [where?.sellerId];
      const filtered = rows
        .filter((r) => sellerIds.includes(r.sellerId) && !r.deletedAt)
        .sort((a, b) => new Date(b.updatedAt) - new Date(a.updatedAt));
      return filtered.map((r) => ({ ...r, media: [], seller: null }));
    },
    count: async ({ where }) => {
      const sellerIds = where?.OR
        ? where.OR.map((part) => part.sellerId)
        : [where?.sellerId];
      return rows.filter((r) => sellerIds.includes(r.sellerId) && !r.deletedAt).length;
    },
    update: async ({ where, data }) => {
      const row = rows.find((r) => r.id === where.id);
      Object.assign(row, data);
      return { ...row, media: [], seller: null };
    },
  };
}

function loadService(store) {
  require.cache[DATABASE] = {
    id: DATABASE, filename: DATABASE, loaded: true,
    exports: { getStore: () => store, getReadStore: () => store },
  };
  delete require.cache[SERVICE];
  return require(SERVICE);
}

function makeStore({ profileRows = [], productRows = [], userRows = [] }) {
  const calls = { profiles: [], profileCreates: [], productLookups: [] };
  const store = {
    sellerProfile: {
      findUnique: async ({ where, select }) => {
        calls.profiles.push(['findUnique', where]);
        // Facade semantics: findUnique({ where: { userId } }) reads the doc
        // keyed by userId, so it only hits profiles whose doc id IS the uid.
        const hit = profileRows.find((p) => p.id === where.userId);
        if (!hit) return null;
        if (select) {
          const out = {};
          for (const k of Object.keys(select)) out[k] = hit[k];
          return out;
        }
        return hit;
      },
      findFirst: async ({ where, select }) => {
        calls.profiles.push(['findFirst', where]);
        const hit = profileRows.find((p) => p.userId === where.userId);
        if (!hit) return null;
        if (select) {
          const out = {};
          for (const k of Object.keys(select)) out[k] = hit[k];
          return out;
        }
        return hit;
      },
      create: async ({ data, select }) => {
        calls.profileCreates.push(data);
        const created = { id: data.userId, ...data };
        if (select) {
          const out = {};
          for (const k of Object.keys(select)) out[k] = created[k];
          return out;
        }
        return created;
      },
    },
    product: sellerProductsMock(productRows),
    user: {
      findUnique: async ({ where }) => {
        const hit = userRows.find((u) => u.id === where.id);
        return hit || null;
      },
    },
  };
  return { store, calls };
}

afterEach(() => {
  for (const k of [DATABASE, SERVICE]) delete require.cache[k];
});

describe('legacy seller recovery', () => {
  it('returns the keyed profile when one exists (no provisioning)', async () => {
    const { store, calls } = makeStore({
      profileRows: [{ id: PROFILE_ID, userId: UID, storeName: 'Duka' }],
    });
    const service = loadService(store);

    const profile = await service.requireSellerProfile(UID);

    assert.equal(profile.id, PROFILE_ID);
    assert.equal(profile.storeName, 'Duka');
    assert.equal(calls.profileCreates.length, 0);
  });

  it('finds a uuid-keyed legacy profile via the userId field', async () => {
    const { store, calls } = makeStore({
      profileRows: [{ id: UUID_ID, userId: UID, storeName: 'Duka ya Kale' }],
    });
    const service = loadService(store);

    const profile = await service.requireSellerProfile(UID);

    assert.equal(profile.id, UUID_ID);
    assert.deepEqual(calls.profiles[0][0], 'findUnique');
    assert.deepEqual(calls.profiles[1][0], 'findFirst');
    assert.equal(calls.profileCreates.length, 0);
  });

  it('auto-provisions from legacy products when no profile doc exists', async () => {
    const { store, calls } = makeStore({
      productRows: [
        { id: 'legacyA', sellerId: UID, title: 'Viatu', sellerName: 'Panther', updatedAt: '2026-01-01T00:00:00Z' },
      ],
      userRows: [{ id: UID, displayName: 'Juma' }],
    });
    const service = loadService(store);

    const profile = await service.requireSellerProfile(UID);

    assert.equal(calls.profileCreates.length, 1);
    const data = calls.profileCreates[0];
    assert.equal(data.userId, UID);
    assert.equal(data.storeName, 'Panther'); // legacy sellerName beats displayName
    assert.equal(data.sellerStatus, 'active');
    assert.equal(data.verificationStatus, 'pending');
    assert.ok(data.storeSlug.endsWith(`-${UID.slice(0, 8)}`));
    assert.equal(profile.id, UID); // keyed by userId, so legacy sellerId matches
    assert.equal(profile.storeName, 'Panther');
  });

  it('falls back to the account display name when legacy products have no sellerName', async () => {
    const { store, calls } = makeStore({
      productRows: [
        { id: 'legacyB', sellerId: UID, title: 'Kofia', sellerName: null, updatedAt: '2026-02-01T00:00:00Z' },
      ],
      userRows: [{ id: UID, displayName: 'Bibi Mariamu' }],
    });
    const service = loadService(store);

    const profile = await service.requireSellerProfile(UID);

    assert.equal(calls.profileCreates[0].storeName, 'Bibi Mariamu');
  });

  it('still throws 404 for a plain user with no products', async () => {
    const { store, calls } = makeStore({
      userRows: [{ id: UID, displayName: 'Sio Muuzaji' }],
    });
    const service = loadService(store);

    await assert.rejects(service.requireSellerProfile(UID), (err) => {
      assert.equal(err.status, 404);
      assert.equal(err.message, 'SELLER_PROFILE_NOT_FOUND');
      return true;
    });
    assert.equal(calls.profileCreates.length, 0);
  });

  it('lists products under both the profile id and the legacy uid, deduped', async () => {
    const { store } = makeStore({
      productRows: [
        { id: 'p1', sellerId: PROFILE_ID, title: 'New', updatedAt: '2026-03-01T00:00:00Z' },
        { id: 'p2', sellerId: UID, title: 'Legacy', updatedAt: '2026-03-02T00:00:00Z' },
        { id: 'p3', sellerId: UID, title: 'Legacy2', updatedAt: '2026-03-03T00:00:00Z' },
      ],
    });
    const service = loadService(store);

    const { items, pagination } = await service.listSellerProducts({
      sellerProfileId: PROFILE_ID,
      userId: UID,
    });

    assert.equal(pagination.total, 3);
    assert.deepEqual(items.map((p) => p.id), ['p3', 'p2', 'p1']);
  });

  it('owns a legacy uid-shape product through a uuid-keyed profile', async () => {
    const { store } = makeStore({
      profileRows: [{ id: UUID_ID, userId: UID, storeName: 'Duka ya Kale' }],
      productRows: [
        { id: 'pLegacy', sellerId: UID, title: 'Kipande', updatedAt: '2026-01-01T00:00:00Z' },
      ],
    });
    const service = loadService(store);

    const owned = await service.getOwnedProduct({
      id: 'pLegacy',
      sellerProfileId: UUID_ID,
      userId: UID,
    });

    assert.equal(owned.id, 'pLegacy');
  });

  it('rejects ownership of another seller\u2019s product', async () => {
    const { store } = makeStore({
      productRows: [
        { id: 'pOther', sellerId: 'someone-else', title: 'Si Yangu', updatedAt: '2026-01-01T00:00:00Z' },
      ],
    });
    const service = loadService(store);

    await assert.rejects(
      service.getOwnedProduct({ id: 'pOther', sellerProfileId: PROFILE_ID, userId: UID }),
      (err) => err.message === 'PRODUCT_NOT_FOUND'
    );
  });

  it('publishes toggle hits both identities (publish/unpublish path)', async () => {
    const { store } = makeStore({
      profileRows: [{ id: PROFILE_ID, userId: UID, storeName: 'Duka' }],
      productRows: [
        { id: 'pLegacy', sellerId: UID, title: 'Kipande', stock: 5, price: 10000, updatedAt: '2026-01-01T00:00:00Z' },
      ],
    });
    const service = loadService(store);

    const updated = await service.setStatus({
      id: 'pLegacy',
      sellerProfileId: PROFILE_ID,
      userId: UID,
      status: 'published',
    });

    assert.equal(updated.status, 'published');
  });
});