'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

const indexes = JSON.parse(
  fs.readFileSync(path.join(__dirname, '..', '..', 'firestore.indexes.json'), 'utf8'),
);

function hasComposite(collection, fields) {
  return (indexes.indexes || []).some((idx) => {
    if (idx.collectionGroup !== collection) return false;
    if (!idx.fields || idx.fields.length !== fields.length) return false;
    return fields.every((f, i) =>
      idx.fields[i].fieldPath === f.fieldPath && idx.fields[i].order === f.order,
    );
  });
}

test('firestore.indexes.json is valid and lists production-failing composites', () => {
  assert.ok(Array.isArray(indexes.indexes));
  assert.equal(
    hasComposite('refunds', [
      { fieldPath: 'status', order: 'ASCENDING' },
      { fieldPath: 'createdAt', order: 'DESCENDING' },
    ]),
    true,
    'refunds status+createdAt desc',
  );
  assert.equal(
    hasComposite('sellerProfiles', [
      { fieldPath: 'verificationStatus', order: 'ASCENDING' },
      { fieldPath: 'createdAt', order: 'DESCENDING' },
    ]),
    true,
    'sellerProfiles verificationStatus+createdAt desc',
  );
  assert.equal(
    hasComposite('payoutTransactions', [
      { fieldPath: 'status', order: 'ASCENDING' },
      { fieldPath: 'createdAt', order: 'ASCENDING' },
    ]),
    true,
    'payoutTransactions status+createdAt asc',
  );
});
