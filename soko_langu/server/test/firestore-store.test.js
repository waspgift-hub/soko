const { test } = require('node:test');
const assert = require('node:assert/strict');

// In-memory Firestore fake implementing the surface firestore-store.js uses:
// collection().doc().{get,set,update,delete}, collection().where().limit().get(),
// batch().{set,update,delete,commit}, listCollections(), runTransaction.
// No emulator, no credentials — mirrors commerce-store's injected seam style.
function createFakeDb(seed = {}) {
  const collections = new Map(); // name -> Map(docId -> data | null=deleted)

  function ensureCol(name) {
    if (!collections.has(name)) collections.set(name, new Map());
    return collections.get(name);
  }

  // Seed: { users: { u1: {...} }, ... }
  for (const [name, docs] of Object.entries(seed)) {
    const col = ensureCol(name);
    for (const [id, data] of Object.entries(docs)) col.set(id, data);
  }

  function clone(v) {
    if (v === null || v === undefined) return v;
    if (v instanceof Date) return new Date(v.getTime());
    if (Array.isArray(v)) return v.map(clone);
    if (typeof v === 'object') {
      const out = {};
      for (const [k, x] of Object.entries(v)) out[k] = clone(x);
      return out;
    }
    return v;
  }

  function valEq(a, b) {
    const na = a instanceof Date ? a.getTime() : (typeof a === 'bigint' ? Number(a) : a);
    const nb = b instanceof Date ? b.getTime() : (typeof b === 'bigint' ? Number(b) : b);
    return na === nb;
  }

  function matchesOp(docVal, op, value) {
    if (op === '==') return valEq(docVal, value);
    if (op === 'array-contains') return Array.isArray(docVal) && docVal.some((x) => valEq(x, value));
    if (op === '>') return docVal > value;
    if (op === '>=') return docVal >= value;
    if (op === '<') return docVal < value;
    if (op === '<=') return docVal <= value;
    if (op === '!=') return !valEq(docVal, value);
    return false;
  }

  function compareVals(a, b) {
    const na = a instanceof Date ? a.getTime() : (a === undefined || a === null ? NaN : a);
    const nb = b instanceof Date ? b.getTime() : (b === undefined || b === null ? NaN : b);
    const aNan = Number.isNaN(na);
    const bNan = Number.isNaN(nb);
    if (aNan && bNan) return 0;
    if (aNan) return 1;
    if (bNan) return -1;
    if (na < nb) return -1;
    if (na > nb) return 1;
    return 0;
  }

  class DocumentSnapshot {
    constructor(id, data) {
      this.id = id;
      this._data = clone(data);
    }
    get exists() { return this._data !== null && this._data !== undefined; }
    data() { return clone(this._data); }
    ref = null;
  }

  class DocumentReference {
    constructor(colName, id) {
      this.colName = colName;
      this.id = id;
      this.path = `${colName}/${id}`;
    }
    async get() {
      const col = ensureCol(this.colName);
      const data = col.has(this.id) ? col.get(this.id) : null;
      return new DocumentSnapshot(this.id, data);
    }
    async set(data, opts = {}) {
      const col = ensureCol(this.colName);
      if (opts.merge) {
        const existing = col.get(this.id);
        col.set(this.id, { ...(existing || {}), ...clone(data) });
      } else {
        col.set(this.id, clone(data));
      }
      return null;
    }
    async update(patch) {
      const col = ensureCol(this.colName);
      const existing = col.get(this.id) || {};
      col.set(this.id, { ...clone(existing), ...clone(patch) });
      return null;
    }
    async delete() {
      ensureCol(this.colName).set(this.id, null);
      return null;
    }
  }

  class QuerySnapshot {
    constructor(docs) {
      this.docs = docs;
    }
    get empty() { return this.docs.length === 0; }
    get size() { return this.docs.length; }
    forEach(cb) { this.docs.forEach(cb); }
  }

  class Query {
    constructor(colName, filters = [], orderField = null, orderDir = 'asc', limitN = null) {
      this.colName = colName;
      this.filters = filters;
      this.orderField = orderField;
      this.orderDir = orderDir;
      this.limitN = limitN;
    }
    where(field, op, value) {
      return new Query(this.colName, [...this.filters, { field, op, value }], this.orderField, this.orderDir, this.limitN);
    }
    orderBy(field, dir = 'asc') {
      return new Query(this.colName, this.filters, field, dir, this.limitN);
    }
    limit(n) {
      return new Query(this.colName, this.filters, this.orderField, this.orderDir, n);
    }
    async get() {
      const col = ensureCol(this.colName);
      let entries = [...col.entries()].filter(([, data]) => data !== null && data !== undefined);
      for (const { field, op, value } of this.filters) {
        entries = entries.filter(([, data]) => matchesOp(data[field], op, value));
      }
      if (this.orderField) {
        entries.sort((a, b) => compareVals(a[1][this.orderField], b[1][this.orderField]) * (this.orderDir === 'desc' ? -1 : 1));
      }
      if (this.limitN != null) entries = entries.slice(0, this.limitN);
      return new QuerySnapshot(entries.map(([id, data]) => new DocumentSnapshot(id, data)));
    }
  }

  class CollectionReference {
    constructor(name) { this.name = name; this.path = name; }
    doc(id) {
      if (id === undefined) {
        id = `auto_${ensureCol(this.name).size + 1}_${Math.random().toString(36).slice(2, 8)}`;
        ensureCol(this.name).set(id, null);
      }
      return new DocumentReference(this.name, String(id));
    }
    where(field, op, value) { return new Query(this.name, [{ field, op, value }]); }
    orderBy(field, dir) { return new Query(this.name, [], field, dir); }
    limit(n) { return new Query(this.name, [], null, 'asc', n); }
    get() { return new Query(this.name).get(); }
  }

  const db = {
    collections,
    collection: (name) => new CollectionReference(name),
    async listCollections() {
      return [...collections.keys()].map((id) => ({ id }));
    },
    batch() {
      const ops = [];
      return {
        set(ref, data, opts) { ops.push({ type: 'set', ref, data: clone(data), opts }); return this; },
        update(ref, data) { ops.push({ type: 'update', ref, data: clone(data) }); return this; },
        delete(ref) { ops.push({ type: 'delete', ref }); return this; },
        async commit() {
          for (const op of ops) {
            if (op.type === 'set') await op.ref.set(op.data, op.opts);
            if (op.type === 'update') await op.ref.update(op.data);
            if (op.type === 'delete') await op.ref.delete();
          }
          return [];
        },
      };
    },
    // Minimal single-op transaction: execute the callback against a writable
    // snapshot and commit if it resolves (used to exercise transactional
    // write path without concurrency semantics).
    async runTransaction(fn) {
      const tx = {
        get: async (ref) => ref.get(),
        set: (ref, data, opts) => ref.pendingSet({ data: clone(data), opts }),
        update: (ref, data) => ref.pendingSet({ data: clone(data), opts: { merge: true } }),
        delete: (ref) => ref.pendingSet({ data: null }),
      };
      const result = await fn(tx);
      const pending = [];
      for (const colName of collections.keys()) {
        const col = collections.get(colName);
        for (const [id, data] of col.entries()) {
          if (data && typeof data === 'object' && data.__pendingTx) {
            pending.push([colName, id, data.__pendingTx]);
          }
        }
      }
      for (const [colName, id, op] of pending) {
        const ref = new DocumentReference(colName, id);
        ensureCol(colName);
        if (op.data === null) await ref.delete();
        else await ref.set(op.data, op.opts);
      }
      return result;
    },
  };

  // helper for tests to inspect raw stored docs
  db.dump = (name) => {
    const col = collections.get(name) || new Map();
    const out = {};
    for (const [id, data] of col.entries()) if (data !== null && data !== undefined) out[id] = clone(data);
    return out;
  };
  db.hasDoc = (name, id, data) => {
    const col = collections.get(name) || new Map();
    const existing = col.get(id);
    if (data === undefined) return existing !== null && existing !== undefined;
    return existing !== null && existing !== undefined && deepEqual(existing, data);
  };

  return db;
}

function deepEqual(a, b) {
  try {
    assert.deepEqual(a, b);
    return true;
  } catch {
    return false;
  }
}

const { storeWith, matchWhere } = require('../src/services/firestore-store');

function setup(seed = {}) {
  const db = createFakeDb(seed);
  const store = storeWith(db);
  return { db, store };
}

// ------------------------------ identity ---------------------------------

test('create writes the doc under the model doc id and returns the business id', async () => {
  const { db, store } = setup();
  const order = await store.order.create({
    data: { id: 'ord-1', orderNumber: 'SV202501010001', buyerId: 'buyer-1', sellerId: 'seller-1', status: 'PENDING_SHIPPING_FEE', PRODUCT_PLACEHOLDER: 1 },
  });
  assert.equal(order.id, 'ord-1');
  assert.ok(db.hasDoc('orders', 'ord-1'));
});

test('keyField models use the business key as the document id', async () => {
  const { db, store } = setup();
  const hold = await store.escrowHold.create({
    data: { orderId: 'ord-eh', amount: 150000n, status: 'holding', payerId: 'buyer-1' },
  });
  assert.equal(hold.id, 'ord-eh');
  assert.ok(db.hasDoc('escrowHolds', 'ord-eh'), 'escrowHold doc must live at escrowHolds/{orderId}');

  const webhook = await store.webhookEvent.create({
    data: { dedupKey: 'cko:evt-9', provider: 'clickpesa', status: 'pending' },
  });
  assert.equal(webhook.id, 'cko:evt-9');
  assert.ok(db.hasDoc('webhookEvents', 'cko:evt-9'), 'webhook doc must live at webhookEvents/{dedupKey}');

  const wallet = await store.wallet.create({ data: { sellerId: 'seller-1', availableBalance: 0n } });
  assert.equal(wallet.id, 'seller-1');
  assert.ok(db.hasDoc('wallets', 'seller-1'));
});

// ---------------------------- read methods -------------------------------

test('findUnique resolves by id and by keyField', async () => {
  const { store } = setup({
    users: { 'u1': { firebaseUid: 'u1', phone: '+255711111111', email: 'a@b.c' } },
  });
  const byId = await store.user.findUnique({ where: { id: 'u1' } });
  assert.equal(byId.id, 'u1');
  assert.equal(byId.phone, '+255711111111');

  const byFirebaseUid = await store.user.findUnique({ where: { firebaseUid: 'u1' } });
  assert.equal(byFirebaseUid.firebaseUid, 'u1');

  assert.equal(await store.user.findUnique({ where: { id: 'nope' } }), null);
});

test('findUnique by non-key unique field falls back to a query', async () => {
  const { store } = setup({
    orders: {
      'o1': { id: 'o1', orderNumber: 'SV0001', buyerId: 'b1', totalAmount: 10000 },
    },
  });
  const order = await store.order.findUnique({ where: { orderNumber: 'SV0001' } });
  assert.equal(order.id, 'o1');
  assert.equal(order.totalAmount, 10000n);
});

test('findFirst respects orderBy', async () => {
  const { store } = setup({
    orders: {
      'o1': { id: 'o1', createdAt: new Date('2025-01-01T00:00:00Z'), status: 'A' },
      'o2': { id: 'o2', createdAt: new Date('2025-01-03T00:00:00Z'), status: 'B' },
      'o3': { id: 'o3', createdAt: new Date('2025-01-02T00:00:00Z'), status: 'A' },
    },
  });
  const newest = await store.order.findFirst({ where: {}, orderBy: { createdAt: 'desc' } });
  assert.equal(newest.id, 'o2');
  const oldest = await store.order.findFirst({ where: {}, orderBy: { createdAt: 'asc' } });
  assert.equal(oldest.id, 'o1');

  const scoped = await store.order.findFirst({ where: { status: 'A' }, orderBy: { createdAt: 'desc' } });
  assert.equal(scoped.id, 'o3');
});

test('findMany supports where, orderBy, skip, take', async () => {
  const { store } = setup({
    orders: {
      'o1': { id: 'o1', status: 'A', amount: 10n },
      'o2': { id: 'o2', status: 'B', amount: 20n },
      'o3': { id: 'o3', status: 'A', amount: 30n },
      'o4': { id: 'o4', status: 'A', amount: 40n },
    },
  });
  const aOrders = await store.order.findMany({ where: { status: 'A' }, orderBy: { amount: 'desc' } });
  assert.deepEqual(aOrders.map((o) => o.id), ['o4', 'o3', 'o1']);

  const page = await store.order.findMany({ where: { status: 'A' }, orderBy: { amount: 'desc' }, skip: 1, take: 1 });
  assert.deepEqual(page.map((o) => o.id), ['o3']);

  const inWhere = await store.order.findMany({ where: { id: { in: ['o1', 'o4'] } } });
  assert.deepEqual(inWhere.map((o) => o.id).sort(), ['o1', 'o4']);
});

test('where operators: gte/lte, not, contains, OR', async () => {
  const { store } = setup({
    otpCredentials: {
      'c1': { id: 'c1', attempts: 2, code: 'abc', status: 'active' },
      'c2': { id: 'c2', attempts: 5, code: 'XYZ9', status: 'expired' },
      'c3': { id: 'c3', attempts: 7, code: 'hello', status: 'active' },
    },
  });
  const low = await store.otpCredential.findMany({ where: { attempts: { lte: 5 } } });
  assert.equal(low.length, 2);
  const high = await store.otpCredential.findMany({ where: { attempts: { gte: 7 } } });
  assert.deepEqual(high.map((c) => c.id), ['c3']);
  const active = await store.otpCredential.findMany({ where: { status: { not: 'expired' } } });
  assert.deepEqual(active.map((c) => c.id).sort(), ['c1', 'c3']);
  const contains = await store.otpCredential.findMany({ where: { code: { contains: 'ELL', mode: 'insensitive' } } });
  assert.deepEqual(contains.map((c) => c.id), ['c3']);
  const or = await store.otpCredential.findMany({ where: { OR: [{ id: 'c1' }, { id: 'c3' }] } });
  assert.deepEqual(or.map((c) => c.id).sort(), ['c1', 'c3']);
});

test('select projects only the requested fields plus id', async () => {
  const { store } = setup({
    products: { 'p1': { id: 'p1', title: 'T', price: 5000, sellerId: 's1' } },
  });
  const slim = await store.product.findUnique({ where: { id: 'p1' }, select: { title: true } });
  assert.deepEqual(slim, { id: 'p1', title: 'T' });
});

// --------------------------- write methods -------------------------------

test('create returns money fields as BigInt and persists as Number', async () => {
  const { db, store } = setup();
  const order = await store.order.create({
    data: { id: 'ord-m', buyerId: 'b', sellerId: 's', productPrice: 120000n, shippingFee: 5000n, platformCommission: 0n, totalAmount: 125000n, status: 'X' },
  });
  assert.equal(order.totalAmount, 125000n);
  assert.equal(typeof order.totalAmount, 'bigint');
  const stored = db.dump('orders')['ord-m'];
  assert.equal(stored.totalAmount, 125000);
  assert.equal(typeof stored.totalAmount, 'number');
});

test('BigInt round-trip across read after write', async () => {
  const { store } = setup({
    wallets: { 's1': { sellerId: 's1', availableBalance: 900000, pendingBalance: 50000 } },
  });
  const w = await store.wallet.findUnique({ where: { sellerId: 's1' } });
  assert.equal(w.availableBalance, 900000n);
  assert.equal(w.pendingBalance, 50000n);

  const updated = await store.wallet.update({ where: { sellerId: 's1' }, data: { availableBalance: 800000n } });
  assert.equal(updated.availableBalance, 800000n);
  assert.equal(updated.pendingBalance, 50000n);
});

test('Date round-trip: createdAt persists as Date and reads back as Date', async () => {
  const { db, store } = setup();
  const before = Date.now();
  const order = await store.order.create({ data: { id: 'ord-d', totalAmount: 0n } });
  const after = Date.now();
  assert.ok(order.createdAt instanceof Date);
  const stored = db.dump('orders')['ord-d'];
  assert.ok(stored.createdAt instanceof Date);
  const t = stored.createdAt.getTime();
  assert.ok(t >= before - 1000 && t <= after + 1000);

  const read = await store.order.findUnique({ where: { id: 'ord-d' } });
  assert.ok(read.createdAt instanceof Date);
});

test('update merges fields and bumps updatedAt', async () => {
  const { db, store } = setup({
    orders: { 'o1': { id: 'o1', status: 'A', totalAmount: 10000, createdAt: new Date('2025-01-01T00:00:00Z') } },
  });
  const res = await store.order.update({ where: { id: 'o1' }, data: { status: 'B' } });
  assert.equal(res.status, 'B');
  assert.equal(res.totalAmount, 10000n, 'unrelated field preserved');
  const stored = db.dump('orders')['o1'];
  assert.equal(stored.status, 'B');
  assert.ok(stored.updatedAt instanceof Date);
});

test('updateMany returns count and updates matches', async () => {
  const { store } = setup({
    orders: {
      'o1': { id: 'o1', status: 'PAYMENT_PENDING' },
      'o2': { id: 'o2', status: 'PAYMENT_PENDING' },
      'o3': { id: 'o3', status: 'COMPLETED' },
    },
  });
  const { count } = await store.order.updateMany({ where: { status: 'PAYMENT_PENDING' }, data: { status: 'EXPIRED' } });
  assert.equal(count, 2);
  const pending = await store.order.findMany({ where: { status: 'PAYMENT_PENDING' } });
  assert.equal(pending.length, 0);
  const expired = await store.order.findMany({ where: { status: 'EXPIRED' } });
  assert.equal(expired.length, 2);
});

test('update honors store atomic increment on Number and BigInt fields', async () => {
  const { store } = setup({
    webhookEvents: { 'k1': { dedupKey: 'k1', attempts: 1 } },
    escrowHolds: { 'o1': { orderId: 'o1', releasedToBuyer: 2000, amount: 10000 } },
  });
  const wh = await store.webhookEvent.update({ where: { id: 'k1' }, data: { attempts: { increment: 1 } } });
  assert.equal(wh.attempts, 2, 'Number increment adds to Number base');

  const hold = await store.escrowHold.update({ where: { id: 'o1' }, data: { releasedToBuyer: { increment: 500n } } });
  assert.equal(hold.releasedToBuyer, 2500n, 'BigInt increment adds to BigInt money field');
});

test('updateMany honors store atomic increment', async () => {
  const { store } = setup({
    webhookEvents: {
      'k1': { dedupKey: 'k1', attempts: 1 },
      'k2': { dedupKey: 'k2', attempts: 3 },
    },
  });
  const { count } = await store.webhookEvent.updateMany({ where: { dedupKey: { in: ['k1', 'k2'] } }, data: { attempts: { increment: 1 } } });
  assert.equal(count, 2);
  const k1 = await store.webhookEvent.findUnique({ where: { dedupKey: 'k1' } });
  const k2 = await store.webhookEvent.findUnique({ where: { dedupKey: 'k2' } });
  assert.equal(k1.attempts, 2);
  assert.equal(k2.attempts, 4);
});

test('upsert creates when absent and updates when present', async () => {
  const { store } = setup();
  const created = await store.payment.upsert({
    where: { idempotencyKey: 'ip-1' },
    create: { idempotencyKey: 'ip-1', amount: 5000n, status: 'pending' },
    update: { status: 'paid' },
  });
  assert.equal(created.status, 'pending');

  const updated = await store.payment.upsert({
    where: { idempotencyKey: 'ip-1' },
    create: { idempotencyKey: 'ip-1', amount: 5000n, status: 'pending' },
    update: { status: 'paid' },
  });
  assert.equal(updated.status, 'paid');
});

test('count returns matching rows', async () => {
  const { store } = setup({
    orders: {
      'o1': { id: 'o1', status: 'A' },
      'o2': { id: 'o2', status: 'A' },
      'o3': { id: 'o3', status: 'B' },
    },
  });
  assert.equal(await store.order.count({ where: { status: 'A' } }), 2);
  assert.equal(await store.order.count(), 3);
});

test('aggregate returns BigInt sums over the where', async () => {
  const { store } = setup({
    orders: {
      'o1': { id: 'o1', status: 'COMPLETED', platformCommission: 10000 },
      'o2': { id: 'o2', status: 'COMPLETED', platformCommission: 20000 },
      'o3': { id: 'o3', status: 'PENDING', platformCommission: 5000 },
    },
  });
  const res = await store.order.aggregate({ where: { status: 'COMPLETED' }, _sum: { platformCommission: true } });
  assert.equal(res._sum.platformCommission, 30000n);
});

test('groupBy buckets by field with _count and BigInt _sum', async () => {
  const { store } = setup({
    orders: {
      'o1': { id: 'o1', status: 'COMPLETED', totalAmount: 100000 },
      'o2': { id: 'o2', status: 'COMPLETED', totalAmount: 50000 },
      'o3': { id: 'o3', status: 'CANCELLED', totalAmount: 25000 },
    },
  });
  const rows = await store.order.groupBy({
    by: ['status'],
    _count: { status: true },
    _sum: { totalAmount: true },
  });
  const byStatus = Object.fromEntries(rows.map((r) => [r.status, r]));
  assert.equal(byStatus.COMPLETED._count.status, 2);
  assert.equal(byStatus.COMPLETED._sum.totalAmount, 150000n);
  assert.equal(byStatus.CANCELLED._count.status, 1);
  assert.equal(byStatus.CANCELLED._sum.totalAmount, 25000n);
});

// ----------------------------- relations ---------------------------------

test('include resolves single relations', async () => {
  const { store } = setup({
    sellerProfiles: { 's1': { id: 's1', storeSlug: 'jua-ish' } },
    users: { 'b1': { id: 'b1', phone: '+255700000000' } },
    orders: { 'o1': { id: 'o1', orderNumber: 'SV1', sellerId: 's1', buyerId: 'b1' } },
  });
  const order = await store.order.findUnique({ where: { id: 'o1' }, include: { seller: true, buyer: true } });
  assert.equal(order.seller.storeSlug, 'jua-ish');
  assert.equal(order.buyer.phone, '+255700000000');
});

test('include with select projects the relation', async () => {
  const { store } = setup({
    orders: { 'o1': { id: 'o1', orderNumber: 'SV1', sellerId: 's1' } },
    sellerProfiles: { 's1': { id: 's1', storeSlug: 'jua-ish', rating: 4.9 } },
  });
  const order = await store.order.findUnique({
    where: { id: 'o1' },
    include: { seller: { select: { storeSlug: true, rating: true } } },
  });
  assert.deepEqual(order.seller, { id: 's1', storeSlug: 'jua-ish', rating: 4.9 });
});

test('insert the data for include with a where filter (many relations)', async () => {
  const { store } = setup({
    sellerProfiles: { 'sp1': { id: 'sp1', storeSlug: 'shop-a' } },
    products: {
      'p1': { id: 'p1', sellerId: 'sp1', title: 'live', deletedAt: null },
      'p2': { id: 'p2', sellerId: 'sp1', title: 'gone', deletedAt: new Date('2025-06-01T00:00:00Z') },
    },
  });
  const profile = await store.sellerProfile.findUnique({
    where: { id: 'sp1' },
    include: { products: { where: { deletedAt: null }, select: { title: true } } },
  });
  assert.deepEqual(profile.products.map((p) => p.title), ['live']);
});

// ------------------------- transactions ----------------------------------

test('interactive $transaction: read-your-writes within the callback', async () => {
  const { db, store } = setup();
  await store.$transaction(async (tx) => {
    const created = await tx.order.create({ data: { id: 'tx-1', buyerId: 'b', status: 'NEW', totalAmount: 70000n } });
    const read = await tx.order.findUnique({ where: { id: 'tx-1' } });
    assert.equal(read.buyerId, 'b');
    assert.equal(read.totalAmount, 70000n);

    const found = await tx.order.findFirst({ where: { status: 'NEW' } });
    assert.equal(found.id, 'tx-1');
  });
  assert.ok(db.hasDoc('orders', 'tx-1'), 'commit persists the buffered write');
});

test('interactive $transaction: update then read sees merged state; commit is atomic', async () => {
  const { db, store } = setup({
    escrowHolds: {
      'ord-eh': { id: 'ord-eh', orderId: 'ord-eh', amount: 100000, status: 'holding', createdAt: new Date('2025-01-01T00:00:00Z') },
    },
  });
  await store.$transaction(async (tx) => {
    const hold = await tx.escrowHold.findUnique({ where: { id: 'ord-eh' } });
    assert.equal(hold.amount, 100000n);
    const updated = await tx.escrowHold.update({ where: { id: 'ord-eh' }, data: { status: 'released' } });
    assert.equal(updated.status, 'released');

    const reRead = await tx.escrowHold.findUnique({ where: { id: 'ord-eh' } });
    assert.equal(reRead.status, 'released', 'read-your-writes after update');

    const fn = await tx.escrowTransaction.create({ data: { type: 'SETTLEMENT_TO_SELLER', amount: 100000n, orderId: 'ord-eh' } });
    assert.ok(fn.id);
  });
  assert.equal(db.dump('escrowHolds')['ord-eh'].status, 'released');
  assert.equal(Object.keys(db.dump('escrowTransactions')).length, 1);
});

test('interactive $transaction: rollback on throw — nothing is persisted', async () => {
  const { db, store } = setup();
  await assert.rejects(
    store.$transaction(async (tx) => {
      await tx.order.create({ data: { id: 'tx-rollback', status: 'X' } });
      await tx.notification.create({ data: { userId: 'u', text: 'nope' } });
      throw new Error('boom');
    }),
    /boom/,
  );
  assert.equal(db.hasDoc('orders', 'tx-rollback'), false, 'no doc after rollback');
  assert.equal(Object.keys(db.dump('notifications')).length, 0);
});

test('interactive $transaction: does not rewite create/update twice', async () => {
  const { db, store } = setup();
  await store.$transaction(async (tx) => {
    await tx.order.create({ data: { id: 'rx-1', status: 'NEW', totalAmount: 1000n } });
    await tx.order.update({ where: { id: 'rx-1' }, data: { status: 'UPDATED' } });
  });
  const stored = db.dump('orders')['rx-1'];
  assert.equal(stored.status, 'UPDATED');
  assert.equal(stored.totalAmount, 1000);
});

test('array-form $transaction executes every op and returns results', async () => {
  const { store } = setup({
    sponsoredCampaigns: {
      'c1': { id: 'c1', status: 'active', spendTzs: 10 },
      'c2': { id: 'c2', status: 'active', spendTzs: 20 },
      'c3': { id: 'c3', status: 'paused', spendTzs: 30 },
    },
  });
  const results = await store.$transaction([
    { model: 'sponsoredCampaign', op: 'updateMany', args: { where: { status: 'active' }, data: { status: 'ended' } } },
    { model: 'sponsoredCampaign', op: 'count', args: { where: { status: 'ended' } } },
  ]);
  assert.equal(results[0].count, 2, 'first op: two campaigns swept');
  assert.equal(results[1], 2, 'second op: count sees the first op within the same batch');
  const remaining = await store.sponsoredCampaign.findMany({ where: { status: 'paused' } });
  assert.equal(remaining.length, 1);
});

test('$queryRaw ping returns query-raw-shaped rows', async () => {
  const { store } = setup({ users: { u1: {} } });
  const rows = await store.$queryRaw`SELECT 1`;
  assert.ok(Array.isArray(rows) && rows.length === 1);
  assert.ok((await store.ping()) === true);
});

// --------------------------- unit: matchWhere ----------------------------

test('matchWhere evaluates BigInt and Date conditions', () => {
  const row = { amount: 5000n, createdAt: new Date('2025-03-01T00:00:00Z'), status: 'A' };
  assert.ok(matchWhere(row, { amount: 5000n }));
  assert.ok(matchWhere(row, { amount: { gte: 5000n } }));
  assert.ok(!matchWhere(row, { amount: { gt: 5000n } }));
  assert.ok(matchWhere(row, { createdAt: { lte: new Date('2025-06-01T00:00:00Z') } }));
  assert.ok(!matchWhere(row, { createdAt: { gt: new Date('2025-06-01T00:00:00Z') } }));
  assert.ok(matchWhere(row, { status: { in: ['A', 'B'] } }));
});