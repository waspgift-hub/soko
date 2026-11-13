const fs = require('fs');
const path = require('path');

const file = path.join(__dirname, '..', 'firestore.indexes.json');
const json = JSON.parse(fs.readFileSync(file, 'utf8'));

const existing = new Set(
  (json.indexes || []).map((i) =>
    `${i.collectionGroup}|${(i.fields || [])
      .map((f) => `${f.fieldPath}:${f.order || f.arrayConfig || ''}`)
      .join(',')}`,
  ),
);

function idx(collectionGroup, fields) {
  const key = `${collectionGroup}|${fields
    .map((f) => `${f.fieldPath}:${f.order || f.arrayConfig || ''}`)
    .join(',')}`;
  if (existing.has(key)) return false;
  existing.add(key);
  return true;
}

const additions = [];

// ── userPublic ────────────────────────────────────────────────────────────
// Intentionally nothing. Client user search (lib/services/user_service.dart
// searchUsers) prefix-scans usernameLower / username / displayNameLower, and
// those need NO composite index: a single-field range query is served by
// Firestore's automatic single-field indexes.
//
// Declaring them anyway is not merely redundant — `firebase deploy` rejects the
// whole index file with:
//   "this index is not necessary, configure using single field index controls"
// so an unnecessary entry blocks every other index in the file from deploying.

// ── money-path list queries the pushed-down store now issues ──────────────
// firestore-store pushes `where` + `orderBy` to Firestore, so each of these
// needs a composite index. Previously they were satisfied by an in-memory sort
// over a bounded scan, which meant they were never exercised — and the audit
// found two of them (walletTransactions, withdrawals) missing, which would fail
// with FAILED_PRECONDITION on a rules/index redeploy.
const composites = [
  ['walletTransactions', [{ fieldPath: 'walletId', order: 'ASCENDING' }, { fieldPath: 'createdAt', order: 'DESCENDING' }]],
  ['walletTransactions', [{ fieldPath: 'walletId', order: 'ASCENDING' }, { fieldPath: 'referenceId', order: 'ASCENDING' }]],
  ['withdrawals', [{ fieldPath: 'sellerId', order: 'ASCENDING' }, { fieldPath: 'createdAt', order: 'DESCENDING' }]],
  ['withdrawals', [{ fieldPath: 'status', order: 'ASCENDING' }, { fieldPath: 'createdAt', order: 'ASCENDING' }]],
  ['orders', [{ fieldPath: 'buyerId', order: 'ASCENDING' }, { fieldPath: 'createdAt', order: 'DESCENDING' }]],
  ['orders', [{ fieldPath: 'sellerId', order: 'ASCENDING' }, { fieldPath: 'createdAt', order: 'DESCENDING' }]],
  ['orders', [{ fieldPath: 'status', order: 'ASCENDING' }, { fieldPath: 'createdAt', order: 'ASCENDING' }]],
  ['orders', [{ fieldPath: 'status', order: 'ASCENDING' }, { fieldPath: 'createdAt', order: 'DESCENDING' }]],
  ['orders', [{ fieldPath: 'deliveredAt', order: 'ASCENDING' }, { fieldPath: 'status', order: 'ASCENDING' }]],
  ['orders', [{ fieldPath: 'orderNumber', order: 'ASCENDING' }]],
  ['payments', [{ fieldPath: 'orderId', order: 'ASCENDING' }, { fieldPath: 'createdAt', order: 'DESCENDING' }]],
  ['payments', [{ fieldPath: 'status', order: 'ASCENDING' }, { fieldPath: 'createdAt', order: 'ASCENDING' }]],
  ['refunds', [{ fieldPath: 'orderId', order: 'ASCENDING' }, { fieldPath: 'createdAt', order: 'DESCENDING' }]],
  ['payoutTransactions', [{ fieldPath: 'withdrawalId', order: 'ASCENDING' }]],
  ['products', [{ fieldPath: 'sellerId', order: 'ASCENDING' }, { fieldPath: 'createdAt', order: 'DESCENDING' }]],
  ['products', [{ fieldPath: 'isActive', order: 'ASCENDING' }, { fieldPath: 'createdAt', order: 'DESCENDING' }]],
  ['products', [{ fieldPath: 'category', order: 'ASCENDING' }, { fieldPath: 'createdAt', order: 'DESCENDING' }]],
  ['reviews', [{ fieldPath: 'sellerId', order: 'ASCENDING' }, { fieldPath: 'createdAt', order: 'DESCENDING' }]],
  ['reviews', [{ fieldPath: 'productId', order: 'ASCENDING' }, { fieldPath: 'createdAt', order: 'DESCENDING' }]],
  ['kycApplications', [{ fieldPath: 'status', order: 'ASCENDING' }, { fieldPath: 'createdAt', order: 'DESCENDING' }]],
  ['sellerProfiles', [{ fieldPath: 'sellerStatus', order: 'ASCENDING' }, { fieldPath: 'createdAt', order: 'DESCENDING' }]],
  ['disputes', [{ fieldPath: 'status', order: 'ASCENDING' }, { fieldPath: 'createdAt', order: 'ASCENDING' }]],
];

for (const [collectionGroup, fields] of composites) {
  if (idx(collectionGroup, fields)) {
    additions.push({ collectionGroup, queryScope: 'COLLECTION', fields });
  }
}

json.indexes = [...(json.indexes || []), ...additions];

// ── TTL policies ──────────────────────────────────────────────────────────
// The audit found no `fieldOverrides` anywhere, so ad_views, anonymous
// product_analytics views, notifications and system_errors grow forever. TTL is
// the cheapest correct fix and costs nothing at query time.
//
// `expireAfter` only works on TIMESTAMP fields, so these are chosen to match
// what the writers actually store.
json.fieldOverrides = json.fieldOverrides || [];
const ttls = [
  ['ad_views', 'timestamp', 90],
  ['system_errors', 'timestamp', 180],
  ['user_sessions', 'lastSeen', 30],
  ['dataDeletionRequests', 'requestedAt', 365],
];
for (const [collectionGroup, fieldPath, days] of ttls) {
  const dup = json.fieldOverrides.some(
    (o) => o.collectionGroup === collectionGroup && o.fieldPath === fieldPath,
  );
  if (dup) continue;
  json.fieldOverrides.push({
    collectionGroup,
    fieldPath,
    indexes: [],
    expireAfter: days,
  });
}

fs.writeFileSync(file, `${JSON.stringify(json, null, 2)}\n`);
console.log(
  `added ${additions.length} indexes, ${json.fieldOverrides.length} TTL policies ` +
    `(total indexes ${json.indexes.length})`,
);