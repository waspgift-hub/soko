// Firestore money core (Phase 5). Every money mutation flows through here so
// Postgres can be retired: a seller wallet lives in `wallets/{sellerUid}` and
// every balance change posts an immutable `walletTransactions/{id}` entry whose
// DOCUMENT ID IS THE IDEMPOTENCY KEY — at-most-once is native to Firestore
// instead of a unique index. Escrow holds + release, webhook dedup, and the
// admin audit trail are in sibling collections.
//
// Money is integer TZS (never floats). Amounts are handled as JS numbers on
// the understood upper bound (TZS fits Number.MAX_SAFE_INTEGER for any amount
// a seller could earn); a str <-> number normalization exists for callers that
// still read BigInt-shaped strings from legacy code.
const { FieldValue } = require('firebase-admin/firestore');
const { getFirebaseFirestore } = require('../config/firebase');

const COLLECTIONS = {
  wallets: 'wallets', // { sellerUid: id }
  ledger: 'walletTransactions', // id = ledgerId (idempotent)
  escrowHolds: 'escrowHolds', // { orderId: id }
  escrowEvents: 'escrowEvents',
  withdrawals: 'withdrawals',
  payoutTransactions: 'payoutTransactions',
  webhooks: 'webhookEvents', // id = dedupKey (idempotent)
  audit: 'auditLogs',
};

const LEDGER_TYPES = {
  PAYMENT_RECEIVED: 'PAYMENT_RECEIVED',
  SHIPPING_FEE_RECEIVED: 'SHIPPING_FEE_RECEIVED',
  COMMISSION_DEBITED: 'COMMISSION_DEBITED',
  SETTLEMENT_CREDITED: 'SETTLEMENT_CREDITED',
  WITHDRAWAL_DEBITED: 'WITHDRAWAL_DEBITED',
  REFUND_PROCESSED: 'REFUND_PROCESSED',
  LEGACY_BALANCE: 'LEGACY_BALANCE',
  ADJUSTMENT: 'ADJUSTMENT',
};

// A ledger entry can only ever be credited once: its doc id IS its
// idempotency key, so a retry with the same key is a no-op `get` that returns
// the original entry.
function buildLedgerId(idempotencyKey) {
  const key = String(idempotencyKey || '').trim();
  if (!key) throw new Error('LEDGER_IDEMPOTENCY_KEY_REQUIRED');
  return key.startsWith('wt_') ? key : `wt_${key}`;
}

// Pure integer money normalization: accepts number | numeric string | BigInt,
// clamps to integer TZS. Rejects NaN/Infinity.
function tzs(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) throw new Error(`INVALID_AMOUNT:${String(value)}`);
  return Math.round(n);
}

// Pure balance math so hermetic unit tests can assert it without Firestore.
function applyBalance(current, amount) {
  const next = tzs(current) + tzs(amount);
  if (next < 0) throw new Error('INSUFFICIENT_FUNDS');
  return next;
}

function serializeWallet(doc) {
  const d = doc.data() || {};
  return {
    sellerId: doc.id,
    availableBalance: tzs(d.availableBalance),
    pendingBalance: tzs(d.pendingBalance),
    frozenBalance: tzs(d.frozenBalance),
    totalEarned: tzs(d.totalEarned),
    totalWithdrawn: tzs(d.totalWithdrawn),
    currency: d.currency || 'TZS',
    status: d.status || 'active',
    createdAt: toISO(d.createdAt),
    updatedAt: toISO(d.updatedAt),
  };
}

function serializeLedger(doc) {
  const d = doc.data() || {};
  return {
    id: doc.id,
    walletId: d.walletId,
    type: d.type,
    amount: tzs(d.amount),
    balanceAfter: tzs(d.balanceAfter),
    referenceType: d.referenceType || null,
    referenceId: d.referenceId || null,
    idempotencyKey: d.idempotencyKey || doc.id,
    description: d.description || null,
    createdAt: toISO(d.createdAt),
  };
}

// Withdrawals are returned to the app as plain JSON: Firestore Timestamps must
// become ISO strings or with `DateTime.tryParse` the app sees an empty date.
function serializeWithdrawal(doc) {
  const d = doc.data ? doc.data() : doc;
  const id = doc.id || d.id;
  return {
    id: String(id),
    sellerId: d.sellerId || null,
    amount: tzs(d.amount),
    provider: d.provider || 'clickpesa',
    status: d.status || 'pending',
    phoneNumber: d.phoneNumber || null,
    idempotencyKey: d.idempotencyKey || null,
    providerPayoutId: d.providerPayoutId || null,
    failureReason: d.failureReason || null,
    processedAt: toISO(d.processedAt),
    createdAt: toISO(d.createdAt),
  };
}

function toISO(value) {
  if (value == null) return null;
  if (typeof value.toDate === 'function') return value.toDate().toISOString();
  if (value instanceof Date) return value.toISOString();
  if (value instanceof FieldValue) return null;
  return String(value);
}

function localDb() {
  return getFirebaseFirestore();
}

// ---- Wallets ---------------------------------------------------------

function walletRef(db, sellerUid) {
  return db.collection(COLLECTIONS.wallets).doc(String(sellerUid));
}

async function getWallet(sellerUid, { createIfMissing = true, db } = {}) {
  const store = db || localDb();
  const ref = walletRef(store, sellerUid);
  const snap = await ref.get();
  if (snap.exists) return serializeWallet(snap);
  if (!createIfMissing) return null;
  const doc = {
    availableBalance: 0,
    pendingBalance: 0,
    frozenBalance: 0,
    totalEarned: 0,
    totalWithdrawn: 0,
    currency: 'TZS',
    status: 'active',
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
  await ref.set(doc, { merge: true });
  const fresh = await ref.get();
  return serializeWallet(fresh);
}

// Reads a page of ledger entries for one wallet (newest first). Page-offset
// slicing over a bounded per-seller history — same HYDRATE_CAP pattern the
// notifications inbox uses.
async function listLedger(sellerUid, { page = 1, limit = 20, db } = {}) {
  const store = db || localDb();
  const take = Math.min(Math.max(1, Number(limit)), 100);
  const skip = (Math.max(1, Number(page)) - 1) * take;
  const snap = await store
    .collection(COLLECTIONS.ledger)
    .where('walletId', '==', String(sellerUid))
    .orderBy('createdAt', 'desc')
    .limit(1000)
    .get();
  const items = snap.docs.map((d) => serializeLedger(d));
  return {
    ledger: items.slice(skip, skip + take),
    pagination: { page: Number(page), limit: take, total: items.length },
  };
}

// Atomic credit/debit of a wallet with its ledger entry. The second arg is the
// idempotency key; a retry with the same key returns the already-posted entry
// and never moves the balance twice.
async function postLedger({
  sellerUid,
  amount,
  type,
  referenceType,
  referenceId,
  idempotencyKey,
  description,
  db,
}) {
  const store = db || localDb();
  const ledgerId = buildLedgerId(idempotencyKey);
  const delta = tzs(amount);

  return store.runTransaction(async (t) => {
    const ledgerRef = store.collection(COLLECTIONS.ledger).doc(ledgerId);
    const ledgerSnap = await t.get(ledgerRef);
    if (ledgerSnap.exists) return serializeLedger(ledgerSnap);

    const wRef = walletRef(store, sellerUid);
    const wSnap = await t.get(wRef);
    const prior = wSnap.exists ? tzs(wSnap.data().availableBalance || 0) : 0;
    const next = applyBalance(prior, delta);

    if (wSnap.exists) {
      t.update(wRef, {
        availableBalance: next,
        totalEarned: delta > 0 ? FieldValue.increment(delta) : FieldValue.increment(0),
        updatedAt: FieldValue.serverTimestamp(),
      });
    } else {
      t.set(wRef, {
        availableBalance: next,
        pendingBalance: 0,
        frozenBalance: 0,
        totalEarned: delta > 0 ? delta : 0,
        totalWithdrawn: 0,
        currency: 'TZS',
        status: 'active',
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    t.set(ledgerRef, {
      walletId: String(sellerUid),
      type,
      amount: Math.abs(delta),
      balanceAfter: next,
      referenceType: referenceType || null,
      referenceId: referenceId || null,
      idempotencyKey: ledgerId,
      description: description || null,
      createdAt: FieldValue.serverTimestamp(),
    });

    return serializeLedger({ id: ledgerRef.id, data: () => ({
      walletId: String(sellerUid),
      type,
      amount: Math.abs(delta),
      balanceAfter: next,
      referenceType: referenceType || null,
      referenceId: referenceId || null,
      idempotencyKey: ledgerId,
      description: description || null,
      createdAt: null,
    }) });
  });
}

async function listWithdrawals(sellerUid, { limit = 500, db } = {}) {
  const store = db || localDb();
  const snap = await store
    .collection(COLLECTIONS.withdrawals)
    .where('sellerId', '==', String(sellerUid))
    .orderBy('createdAt', 'desc')
    .limit(Math.min(Number(limit) || 500, 1000))
    .get();
  return snap.docs.map((d) => serializeWithdrawal(d));
}

// Sums non-cancelled withdrawals since a date (daily cap). Reads at most
// `limit` docs and filters cancelled in memory — withdrawal volume per seller
// per day is small, so a pure-DB SUM() aggregate is not worth a range filter
// that Firestore cannot combine with a status != filter.
async function sumWithdrawalsToday(sellerUid, sinceDate, { db, limit = 500 } = {}) {
  const store = db || localDb();
  const snap = await store
    .collection(COLLECTIONS.withdrawals)
    .where('sellerId', '==', String(sellerUid))
    .orderBy('createdAt', 'desc')
    .limit(limit)
    .get();
  const since = new Date(sinceDate).getTime();
  let total = 0;
  for (const d of snap.docs) {
    const x = d.data();
    if (x.status === 'cancelled') continue;
    const created = x.createdAt && typeof x.createdAt.toDate === 'function'
      ? x.createdAt.toDate().getTime()
      : new Date(x.createdAt || 0).getTime();
    if (created < since) continue;
    total += tzs(x.amount);
  }
  return total;
}

// ---- Escrow ----------------------------------------------------------

function escrowHoldRef(db, orderId) {
  return db.collection(COLLECTIONS.escrowHolds).doc(String(orderId));
}

async function getEscrowHold(orderId, { db } = {}) {
  const store = db || localDb();
  const snap = await escrowHoldRef(store, orderId).get();
  if (!snap.exists) return null;
  const d = snap.data();
  return { orderId, ...d, amount: tzs(d.amount), releasedToBuyer: tzs(d.releasedToBuyer || 0) };
}

async function createEscrowHold({ orderId, paymentId, amount, db } = {}) {
  const store = db || localDb();
  const ref = escrowHoldRef(store, orderId);
  await ref.set({
    orderId: String(orderId),
    paymentId: String(paymentId || null),
    amount: tzs(amount),
    releasedToBuyer: 0,
    status: 'holding',
    createdAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  return getEscrowHold(orderId, { db: store });
}

// Releases escrow to the seller's wallet exactly once. Idempotent on two keys:
// the ledger entry id (`settle_${orderId}`) and the escrowHold `releaseKey`.
// Also closes out the app-facing twin docs (orders + transactions share the
// orderId) so the buyer/seller screens flip to COMPLETED in the same commit.
async function settleEscrowToSeller({
  orderId,
  sellerId,
  amount,
  idempotencyKey,
  commission = 0,
  db,
}) {
  const store = db || localDb();
  const settled = tzs(amount);
  const lm = tzs(commission);
  const sellerReceives = settled - lm;

  return store.runTransaction(async (t) => {
    const holdRef = escrowHoldRef(store, orderId);
    const holdSnap = await t.get(holdRef);
    const current = holdSnap.exists ? holdSnap.data() : null;
    if (current && current.status === 'released') {
      // Already settled — return the recorded outcome without moving money.
      return { alreadySettled: true, sellerReceives, orderId };
    }

    const ledgerId = buildLedgerId(idempotencyKey || `settle_${orderId}`);
    const ledgerRef = store.collection(COLLECTIONS.ledger).doc(ledgerId);
    if ((await t.get(ledgerRef)).exists) {
      return { alreadySettled: true, sellerReceives, orderId };
    }

    // Read-modify-write the wallet balance inside the same transaction.
    const wRef = walletRef(store, sellerId);
    const wSnap = await t.get(wRef);
    const prior = wSnap.exists ? tzs(wSnap.data().availableBalance || 0) : 0;
    const next = applyBalance(prior, sellerReceives);

    if (current) {
      if (current.status === 'disputed') throw new Error('ESCROW_DISPUTED');
      if (current.status === 'refunded') throw new Error('ESCROW_REFUNDED');
      t.update(holdRef, {
        status: 'released',
        releasedAt: FieldValue.serverTimestamp(),
        releaseKey: ledgerId,
      });
    } else {
      t.set(holdRef, {
        orderId: String(orderId),
        amount: settled,
        releasedToBuyer: 0,
        status: 'released',
        releasedAt: FieldValue.serverTimestamp(),
        releaseKey: ledgerId,
      }, { merge: true });
    }

    // Credit the seller wallet (same ledger doc id as above => at-most-once).
    t.set(ledgerRef, {
      walletId: String(sellerId),
      type: LEDGER_TYPES.SETTLEMENT_CREDITED,
      amount: sellerReceives,
      balanceAfter: next,
      referenceType: 'SETTLEMENT',
      referenceId: String(orderId),
      idempotencyKey: ledgerId,
      createdAt: FieldValue.serverTimestamp(),
    });

    if (wSnap.exists) {
      t.update(wRef, {
        availableBalance: next,
        totalEarned: FieldValue.increment(sellerReceives),
        updatedAt: FieldValue.serverTimestamp(),
      });
    } else {
      t.set(wRef, {
        availableBalance: next,
        pendingBalance: 0,
        frozenBalance: 0,
        totalEarned: sellerReceives,
        totalWithdrawn: 0,
        currency: 'TZS',
        status: 'active',
        createdAt: FieldValue.serverTimestamp(),
      });
    }

    // Patch the app-facing docs only when they already exist (the legacypay
    // stack creates them; we must never fabricate orders/transactions docs).
    const orderRef = store.collection('orders').doc(String(orderId));
    if ((await t.get(orderRef)).exists) {
      t.set(orderRef, {
        status: 'completed',
        payoutStatus: 'completed',
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    }
    const txRef = store.collection('transactions').doc(String(orderId));
    if ((await t.get(txRef)).exists) {
      t.set(txRef, {
        status: 'completed',
        sellerReceives,
        payoutStatus: 'completed',
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    }

    // Immutable settlement event for admin/audit timelines.
    t.set(store.collection(COLLECTIONS.escrowEvents).doc(), {
      orderId: String(orderId),
      type: 'ESCROW_RELEASED',
      amount: settled,
      sellerReceives,
      commission: lm,
      ledgerId,
      createdAt: FieldValue.serverTimestamp(),
    });

    return { alreadySettled: false, sellerReceives, orderId };
  });
}

// ---- Webhook outbox (Layer-2 idempotency, now native to Firestore) ----

async function recordWebhookEvent({ provider, dedupKey, type, rawPayload, signature, orderReference, db } = {}) {
  const store = db || localDb();
  const ref = store.collection(COLLECTIONS.webhooks).doc(String(dedupKey));
  const existing = await ref.get();
  if (existing.exists) return { id: ref.id, ...existing.data(), dedupKey, status: existing.data().status };
  await ref.set({
    provider,
    dedupKey,
    type,
    status: 'received',
    rawPayload: rawPayload == null ? null : rawPayload,
    signature: signature || null,
    orderReference: orderReference || null,
    attempts: 0,
    createdAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  return { id: ref.id, provider, dedupKey, type, status: 'received', orderReference: orderReference || null };
}

async function markWebhookStatus(event, status, { error, attempts = 0, db } = {}) {
  if (!event || !event.dedupKey) return;
  const store = db || localDb();
  const ref = store.collection(COLLECTIONS.webhooks).doc(String(event.dedupKey));
  const patch = { status };
  if (status === 'processed') patch.processedAt = FieldValue.serverTimestamp();
  if (status === 'failed') {
    patch.attempts = FieldValue.increment(1);
    patch.lastError = error && error.message ? String(error.message).slice(0, 500) : 'unknown';
  }
  await ref.set(patch, { merge: true });
}

// ---- Audit -----------------------------------------------------------

async function writeAuditLog({
  actorId,
  actorType = 'user',
  action,
  entityType,
  entityId,
  oldState,
  newState,
  requestId,
  ipAddress,
  userAgent,
  db,
}) {
  const store = db || localDb();
  const ref = store.collection(COLLECTIONS.audit).doc();
  await ref.set({
    actorId: actorId || null,
    actorType: actorType || 'user',
    action,
    entityType: entityType || null,
    entityId: entityId || null,
    oldState: oldState == null ? null : oldState,
    newState: newState == null ? null : newState,
    requestId: requestId || null,
    ipAddress: ipAddress || null,
    userAgent: userAgent || null,
    createdAt: FieldValue.serverTimestamp(),
  });
  return ref.id;
}

// Builder-based seam for hermetic tests (mirrors presentation-mirror's
// buildSyncLegacyOrderStatus pattern): pass a fake db to exercise logic
// without credentials.
function storeWith(db) {
  return {
    getWallet: (uid, o) => getWallet(uid, { ...o, db }),
    listLedger: (uid, o) => listLedger(uid, { ...o, db }),
    postLedger: (o) => postLedger({ ...o, db }),
    getEscrowHold: (id) => getEscrowHold(id, { db }),
    createEscrowHold: (o) => createEscrowHold({ ...o, db }),
    settleEscrowToSeller: (o) => settleEscrowToSeller({ ...o, db }),
    listWithdrawals: (uid, o) => listWithdrawals(uid, { ...o, db }),
    recordWebhookEvent: (o) => recordWebhookEvent({ ...o, db }),
    markWebhookStatus: (e, s, o) => markWebhookStatus(e, s, { ...o, db }),
    writeAuditLog: (o) => writeAuditLog({ ...o, db }),
  };
}

module.exports = {
  COLLECTIONS,
  LEDGER_TYPES,
  buildLedgerId,
  tzs,
  applyBalance,
  serializeWallet,
  serializeLedger,
  serializeWithdrawal,
  getWallet,
  listLedger,
  postLedger,
  listWithdrawals,
  sumWithdrawalsToday,
  getEscrowHold,
  createEscrowHold,
  settleEscrowToSeller,
  recordWebhookEvent,
  markWebhookStatus,
  writeAuditLog,
  storeWith,
};