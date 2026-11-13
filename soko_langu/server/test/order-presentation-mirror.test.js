// Presentation-mirror coverage.
//
// The Flutter order screens stream the legacy Firestore `orders/{id}` +
// `transactions/{id}` docs, while the authoritative state lives in the store.
// `syncLegacyOrderStatus` is the only thing that keeps those two in step, so a
// status change that skips it leaves a buyer staring at a screen that contradicts
// the server (paying again, waiting for a quote that was approved an hour ago).
//
// These tests pin the paths that must mirror, using the injectable
// `buildSyncLegacyOrderStatus(db)` seam so no credentials are needed.
const { test, describe } = require('node:test');
const assert = require('node:assert');

const { buildSyncLegacyOrderStatus } = require('../src/modules/legacy-compat/presentation-mirror');
const { legacyStatusOf } = require('../src/modules/legacy-compat/legacy-status');

// Minimal stand-in for the admin Firestore instance the mirror writes through.
function fakeDb({ orderExists = true, txExists = true } = {}) {
  const writes = [];
  return {
    writes,
    collection(name) {
      return {
        doc(id) {
          return {
            get: async () => ({
              exists: name === 'orders' ? orderExists : txExists,
              data: () => ({}),
              id,
            }),
            set: async (patch, opts) => {
              writes.push({ collection: name, id, patch, opts });
            },
          };
        },
      };
    },
  };
}

describe('presentation mirror writes the status the client reads', () => {
  test('projects both docs so the order screen and the tx screen agree', async () => {
    const db = fakeDb();
    const sync = buildSyncLegacyOrderStatus(db);

    await sync({ id: 'ord_1', status: 'ESCROW_HELD', shippingFee: 1500n, totalAmount: 45000n, platformCommission: 4500n });

    assert.strictEqual(db.writes.length, 2, 'both orders/ and transactions/ must be written');
    const [orderWrite, txWrite] = db.writes;
    assert.strictEqual(orderWrite.collection, 'orders');
    assert.strictEqual(txWrite.collection, 'transactions');
    assert.strictEqual(orderWrite.patch.status, legacyStatusOf('ESCROW_HELD'));
    assert.strictEqual(orderWrite.patch.status, txWrite.patch.status);

    // Money fields are mirrored too, and BigInt is narrowed for Firestore.
    assert.strictEqual(orderWrite.patch.shippingCost, 1500);
    assert.strictEqual(orderWrite.patch.totalAmount, 45000);
    assert.strictEqual(orderWrite.patch.platformFee, 4500);
    assert.ok(orderWrite.opts && orderWrite.opts.merge, 'merge must be set or the doc is clobbered');
  });

  test('never creates a doc for an order the app does not know about', async () => {
    const db = fakeDb({ orderExists: false });
    const sync = buildSyncLegacyOrderStatus(db);

    await sync({ id: 'pure_v2_order', status: 'COMPLETED' });

    assert.strictEqual(db.writes.length, 0, 'a pure-v2 order must not gain legacy docs');
  });

  test('a Firestore failure is swallowed — it must never fail the money path', async () => {
    const sync = buildSyncLegacyOrderStatus({
      collection() {
        return {
          doc() {
            return {
              get: async () => {
                throw new Error('firestore unavailable');
              },
              set: async () => {},
            };
          },
        };
      },
    });

    await assert.doesNotReject(() => sync({ id: 'ord_2', status: 'COMPLETED' }));
  });

  test('a null firestore (unconfigured credentials) is a no-op', async () => {
    const sync = buildSyncLegacyOrderStatus(null);
    await assert.doesNotReject(() => sync({ id: 'ord_3', status: 'COMPLETED' }));
  });
});

describe('every status the UI waits on has a legacy spelling', () => {
  // The client compares against these lowercase strings; a canonical state that
  // mirrors to undefined would render as a blank status.
  const CLIENT_EXPECTED = [
    'PENDING_SHIPPING_FEE',
    'SHIPPING_FEE_REVIEW',
    'AWAITING_ESCROW_PAYMENT',
    'PAYMENT_PENDING',
    'ESCROW_HELD',
    'DISPATCHED',
    'DELIVERED',
    'OTP_PENDING',
    'DELIVERY_CONFIRMED',
    'COMPLETED',
    'CANCELLED',
    'EXPIRED',
    'DISPUTED',
    'REFUND_PENDING',
    'REFUNDED',
  ];

  for (const state of CLIENT_EXPECTED) {
    test(`${state} mirrors to a non-empty string`, () => {
      const legacy = legacyStatusOf(state);
      assert.strictEqual(typeof legacy, 'string');
      assert.ok(legacy.length > 0, `${state} produced an empty legacy status`);
      assert.notStrictEqual(legacy, undefined);
    });
  }
});

describe('status-changing paths call the mirror', () => {
  // A regression guard rather than a behavioural test: these routes changed the
  // order status without ever calling syncLegacyOrderStatus, which is exactly
  // how the buyer-visible staleness was introduced in the first place.
  const fs = require('fs');
  const path = require('path');

  // __dirname is <repo>/soko_langu/server/test, and the paths below are
  // repo-relative, so two levels up lands in soko_langu/.
  const read = (rel) =>
    fs.readFileSync(path.resolve(__dirname, '..', '..', rel), 'utf8');

  // `symbol` is what the path must reference. The shipping routes go through a
  // `mirrorQuoteOutcome` wrapper (null-safe, single place) so they call that
  // three times while naming `syncLegacyOrderStatus` only once.
  const cases = [
    ['server/src/modules/shipping/routes.js', 'shipping quote routes', 'mirrorQuoteOutcome(', 3],
    ['server/src/modules/disputes/dispute-service.js', 'dispute resolution', 'syncLegacyOrderStatus(', 1],
    ['server/src/jobs/finance-jobs.js', 'payment-expiry sweep', 'syncLegacyOrderStatus(', 1],
    ['server/src/modules/orders/order-service.js', 'order service (cancel/dispatch/deliver)', 'syncLegacyOrderStatus(', 1],
  ];

  for (const [rel, label, symbol, minimum] of cases) {
    test(`${label} calls the mirror on every status change`, () => {
      const src = read(rel);
      const calls = (src.match(new RegExp(symbol.replace(/[(]/g, '\\('), 'g')) || []).length;
      assert.ok(
        calls >= minimum,
        `${rel} should call ${symbol} at least ${minimum}x, found ${calls}`,
      );
    });
  }

  test('the mirror is never awaited from inside a store transaction callback', () => {
    // A raw Firestore write inside $transaction is not part of the buffered
    // batch, so it survives a rollback and would tell the client the order
    // changed when the change was undone.
    for (const rel of [
      'server/src/modules/orders/order-service.js',
      'server/src/modules/disputes/dispute-service.js',
      'server/src/jobs/finance-jobs.js',
    ]) {
      const lines = read(rel).split(/\r?\n/);
      let depth = null;
      lines.forEach((line, i) => {
        if (/\$transaction\s*\(/.test(line)) depth = 0;
        else if (depth !== null) {
          if (/syncLegacyOrderStatus\s*\(/.test(line)) {
            assert.fail(
              `${rel}:${i + 1} calls syncLegacyOrderStatus inside a transaction callback`,
            );
          }
          // Track brace depth to find where the callback ends.
          for (const ch of line) {
            if (ch === '{') depth++;
            else if (ch === '}') depth--;
          }
          if (depth <= 0) depth = null;
        }
      });
    }
  });
});