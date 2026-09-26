const { test } = require('node:test');
const assert = require('node:assert');
const { legacyStatusOf, LEGACY_STATUS } = require('../src/modules/legacy-compat/legacy-status');
const { ORDER_STATES } = require('../src/modules/orders/order-state-machine');
const { buildSyncLegacyOrderStatus } = require('../src/modules/legacy-compat/presentation-mirror');

test('LEGACY_STATUS has an explicit entry for every v2 order state', () => {
  for (const v2 of Object.values(ORDER_STATES)) {
    assert.ok(v2 in LEGACY_STATUS, `explicit mapping missing for ${v2}`);
  }
});

test('legacyStatusOf maps the money-relevant states to legacy vocabulary', () => {
  assert.strictEqual(LEGACY_STATUS.in_escrow, 'escrow_hold');
  assert.strictEqual(LEGACY_STATUS.ready_to_dispatch, 'escrow_hold');
  assert.strictEqual(LEGACY_STATUS.otp_pending, 'delivered');
  assert.strictEqual(LEGACY_STATUS.completed, 'completed');
  assert.strictEqual(LEGACY_STATUS.cancelled, 'cancelled');
  assert.strictEqual(LEGACY_STATUS.disputed, 'disputed');
  assert.strictEqual(LEGACY_STATUS.failed, 'failed');
  assert.strictEqual(legacyStatusOf('unknown_state'), 'pending');
});

test('syncLegacyOrderStatus no-ops when no Firestore is configured', async () => {
  const sync = buildSyncLegacyOrderStatus(null);
  await sync({ id: 'o-1', status: 'in_escrow' });
  assert.ok(true);
});

test('syncLegacyOrderStatus creates a presentation mirror for v2 orders', async () => {
  const writes = [];
  const db = {
    collection() {
      return {
        doc() {
          return {
            async get() { return { exists: false }; },
            async set(data, opts) { writes.push({ data, opts }); },
          };
        },
      };
    },
  };
  const sync = buildSyncLegacyOrderStatus(db);
  await sync({ id: 'or-pure-v2', status: 'completed' });
  assert.strictEqual(writes.length, 2);
});

test('syncLegacyOrderStatus updates existing mirror docs with the legacy status', async () => {
  const writes = [];
  const db = {
    collection(name) {
      return {
        doc(id) {
          return {
            async get() { return { exists: true }; },
            async set(data, opts) { writes.push({ name, id, data, opts }); },
          };
        },
      };
    },
  };
  const sync = buildSyncLegacyOrderStatus(db);
  await sync({ id: 'or-1', status: 'in_escrow' });

  assert.strictEqual(writes.length, 2);
  assert.deepStrictEqual(writes.map((w) => w.name), ['orders', 'transactions']);
  assert.strictEqual(writes[0].id, 'or-1');
  assert.strictEqual(writes[0].data.status, 'escrow_hold');
  assert.deepStrictEqual(writes[0].opts, { merge: true });
  assert.strictEqual(writes[1].data.status, 'escrow_hold');
});

test('a Firestore failure never throws out of the sync', async () => {
  const db = {
    collection() {
      throw new Error('firestore down');
    },
  };
  const sync = buildSyncLegacyOrderStatus(db);
  await sync({ id: 'or-2', status: 'completed' });
  assert.ok(true);
});