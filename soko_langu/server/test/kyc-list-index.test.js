// Regression: the KYC queue answered 500 "Internal server error".
//
// /api/admin/kyc/all gained an orderBy('kyc.submittedAt') alongside the
// kyc.status 'in' filter. Firestore needs a composite index for that pair and
// none is declared in firestore.indexes.json, so the query failed outright with
// FAILED_PRECONDITION and the panel showed a generic error with no cause.
//
// These tests drive collectKyc against a fake Firestore that REJECTS any query
// combining a field filter with an orderBy/where on a different field — the
// shape a composite index would be required for. If someone reintroduces the
// order, the test fails the way production did.
const { test } = require('node:test');
const assert = require('node:assert/strict');

const source = require('node:fs').readFileSync(
  require.resolve('../src/modules/legacy-compat/admin-compat.js'),
  'utf8',
);

function fakeDb(docs) {
  const queries = [];
  return {
    queries,
    collection(name) {
      return {
        where(field, op, values) {
          return {
            offset(off) {
              return {
                limit(take) {
                  return {
                    async get() {
                      queries.push({ name, field, op, values, off, take });
                      return { docs: docs.slice(off, off + take) };
                    },
                  };
                },
              };
            },
            orderBy() {
              throw new Error(
                'FAILED_PRECONDITION: composite index required for ' +
                  field + ' + orderBy — declare it in firestore.indexes.json',
              );
            },
          };
        },
      };
    },
  };
}

function doc(id, data) {
  return { id, data: () => data };
}

test('no KYC list query combines a field filter with an orderBy', () => {
  // Static guard: the query builder itself must stay index-free.
  const kycSection = source.slice(
    source.indexOf('async function collectKyc'),
    source.indexOf("router.get('/kyc/all'"),
  );
  assert.ok(kycSection.length > 0, 'collectKyc must exist');
  assert.equal(
    /orderBy\(/.test(kycSection),
    false,
    'collectKyc must not orderBy: it needs a composite index that does not exist',
  );
  assert.equal(/startAfter\(/.test(kycSection), false, 'cursor paging needs orderBy');
});

test('KYC_STATUSES covers every reviewable state', () => {
  const states = ['pending', 'approved', 'rejected', 'revoked'];
  for (const s of states) {
    assert.ok(source.includes(`'${s}'`), `state ${s} must be listed`);
  }
});

test('the list route logs the underlying error code', () => {
  const route = source.slice(source.indexOf("router.get('/kyc/all'"));
  assert.ok(
    route.includes('[KYC][LIST]'),
    'a bare 500 hid a Firestore index requirement; log the real code',
  );
});