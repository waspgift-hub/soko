// Admin moderation surface: product delete/restore.
//
// Product delete is SOFT on purpose. A product can be referenced by live
// orders, escrow holds and receipts, so a hard delete would orphan money
// records; restore returns the row to 'draft' rather than straight to
// 'published' so a moderator cannot silently re-list it.
//
// product-service binds getStore at require time, so the store seam is patched
// BEFORE the service is loaded (same approach as cancel-refund.test.js).
const { test, beforeEach } = require('node:test');
const assert = require('node:assert/strict');

const state = { rows: [] };

const DB = require('../src/config/database');

DB.getStore = () => ({
  product: {
    findUnique: async ({ where }) => {
      const row = state.rows.find((r) => r.id === where.id) || null;
      return row ? { ...row } : null;
    },
    update: async ({ where, data }) => {
      const row = state.rows.find((r) => r.id === where.id);
      if (!row) throw new Error('update target missing: ' + where.id);
      Object.assign(row, data);
      return { ...row };
    },
  },
});

const service = require('../src/modules/products/product-service');

beforeEach(() => {
  state.rows = [];
});

test('adminSetDeleted soft-deletes: stamps status and deletedAt, keeps the row', async () => {
  state.rows.push({ id: 'p1', status: 'published', deletedAt: null });
  const out = await service.adminSetDeleted({ id: 'p1', deleted: true });
  assert.equal(out.status, 'deleted');
  assert.ok(out.deletedAt instanceof Date, 'deletedAt must be stamped');
  assert.equal(state.rows.length, 1, 'the row must survive a soft delete');
});

test('adminSetDeleted restore returns the row to draft, never published', async () => {
  state.rows.push({ id: 'p1', status: 'deleted', deletedAt: new Date() });
  const out = await service.adminSetDeleted({ id: 'p1', deleted: false });
  assert.equal(out.status, 'draft');
  assert.equal(out.deletedAt, null);
});

test('adminSetDeleted is idempotent in both directions', async () => {
  state.rows.push({ id: 'p1', status: 'deleted', deletedAt: new Date() });
  const first = state.rows[0].deletedAt;
  const again = await service.adminSetDeleted({ id: 'p1', deleted: true });
  assert.equal(again.deletedAt, first, 're-deleting must not restamp deletedAt');

  state.rows.push({ id: 'p2', status: 'published', deletedAt: null });
  const live = await service.adminSetDeleted({ id: 'p2', deleted: false });
  assert.equal(live.status, 'published', 'restoring a live row must not demote it to draft');
});

test('adminSetDeleted rejects an unknown product with 404', async () => {
  await assert.rejects(
    service.adminSetDeleted({ id: 'missing', deleted: true }),
    (e) => e.status === 404,
  );
});