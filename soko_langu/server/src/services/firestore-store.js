// Firestore entity store — the single data layer for the business path.
//
// Every module that used to call Prisma `<model>.<op>(...)` now lands here.
// Firestore is the ONLY store: no Postgres mirror, no second source of truth.
// Method names keep the Prisma shape (`findUnique`, `create`, `$transaction`,
// `$queryRaw`) so the app wire contract and service logic are untouched by the
// storage-engine swap.
//
// Conventions:
//   - One document per entity. The document id is the model's business key
//     when one exists (escrowHold -> orderId, webhookEvent -> dedupKey,
//     wallet -> sellerId, user -> firebaseUid) so at-most-once is native to
//     Firestore. Other models use a generated uuid.
//   - Money is integer TZS: BigInt inside the facade (mirror of the row a
//     service expects), a JS Number at the Firestore boundary.
//   - Timestamps are Firestore serverTimestamp-compatible Dates; read back as
//     Date so `.toISOString()`/`new Date()` semantics match Prisma.
//   - Queries push down a single equality filter and post-filter the rest in
//     memory (volume is small; avoids composite-index requirements).
//   - Interactive $transaction is a buffered overlay: reads see own-writes via
//     the overlay, writes are buffered and flushed atomically via one batch on
//     success. A throwing callback rolls back (nothing is flushed).
const { randomUUID } = require('crypto');
const { getFirebaseFirestore } = require('../config/firebase');

// Page sizes. There is no longer a "read ceiling" — these bound a SINGLE
// Firestore read, and the query layer pages until the answer is complete.
//
//   DEFAULT_PAGE_SIZE  a bounded page when the caller gave no `take`
//   SCAN_PAGE_SIZE     batch size for the residual (post-filter) scan path
//   HARD_PAGE_CAP      ceiling on one caller-supplied `take`, so a single
//                      request can never ask the database for the world
const DEFAULT_PAGE_SIZE = 200;
const SCAN_PAGE_SIZE = 300;
const HARD_PAGE_CAP = 1000;

// model -> collection + identity + money fields.
// `keyField` (when set) is the field whose value IS the document id AND the
// returned row's `id` (identity collapse: user.id := firebaseUid, etc).
const MODELS = {
  user: { col: 'users', keyField: 'firebaseUid', unique: ['firebaseUid', 'phone', 'email', 'username'] },
  sellerProfile: { col: 'sellerProfiles', keyField: 'userId', unique: ['userId', 'storeSlug'] },
  product: { col: 'products', money: ['price'] },
  productMedia: { col: 'productMedia', unique: ['productId'] },
  category: { col: 'categories' },
  order: { col: 'orders', money: ['productPrice', 'shippingFee', 'platformCommission', 'totalAmount'], unique: ['orderNumber', 'legacyFirestoreId'] },
  orderItem: { col: 'orderItems', money: ['unitPrice', 'totalPrice'] },
  shippingQuote: { col: 'shippingQuotes', money: ['amount'] },
  payment: { col: 'payments', money: ['amount'], unique: ['idempotencyKey'] },
  paymentAttempt: { col: 'paymentAttempts' },
  escrowHold: { col: 'escrowHolds', keyField: 'orderId', money: ['amount', 'releasedToBuyer'], unique: ['orderId', 'paymentId'] },
  escrowTransaction: { col: 'escrowTransactions', money: ['amount'], unique: ['requestId'] },
  commissionTransaction: { col: 'commissionTransactions', money: ['amount'] },
  refund: { col: 'refunds', money: ['amount'], unique: ['correlationId'] },
  payoutTransaction: { col: 'payoutTransactions', money: ['amount'], unique: ['withdrawalId'] },
  receipt: { col: 'receipts', money: ['amount'] },
  wallet: { col: 'wallets', keyField: 'sellerId', money: ['availableBalance', 'pendingBalance', 'frozenBalance', 'totalEarned', 'totalWithdrawn'], unique: ['sellerId'] },
  walletLedgerEntry: { col: 'walletTransactions', money: ['amount', 'balanceAfter'], unique: ['idempotencyKey'] },
  withdrawal: { col: 'withdrawals', money: ['amount'], unique: ['idempotencyKey'] },
  otpCredential: { col: 'otpCredentials', keyField: 'orderId' },
  dispute: { col: 'disputes' },
  disputeEvidence: { col: 'disputeEvidence' },
  notification: { col: 'notifications' },
  auditLog: { col: 'auditLogs' },
  webhookEvent: { col: 'webhookEvents', keyField: 'dedupKey' },
  address: { col: 'addresses' },
  userSetting: { col: 'userSettings' },
  device: { col: 'devices' },
  referral: { col: 'referrals', money: ['rewardAmount'], unique: ['code'] },
  boost: { col: 'boosts', money: ['price'] },
  kycApplication: { col: 'kycApplications', unique: ['userId'] },
  moderationReport: { col: 'moderationReports' },
  adminSetting: { col: 'adminSettings', keyField: 'key' },
  reconciliation: { col: 'reconciliations' },
  dataDeletionRequest: { col: 'dataDeletionRequests' },
};

// Relation resolution for `include`. `local` is this model's field holding the
// link value; `remote` is the target field on the related model ('id' resolves
// the target's doc id directly).
const RELATIONS = {
  order: {
    seller: { model: 'sellerProfile', local: 'sellerId', remote: 'id' },
    buyer: { model: 'user', local: 'buyerId', remote: 'id' },
  },
  product: { sellerProfile: { model: 'sellerProfile', local: 'sellerId', remote: 'id' } },
  sellerProfile: {
    wallet: { model: 'wallet', local: 'id', remote: 'sellerId' },
    products: { model: 'product', local: 'id', remote: 'sellerId', many: true },
  },
  user: { sellerProfile: { model: 'sellerProfile', local: 'id', remote: 'userId' } },
  refund: {
    order: { model: 'order', local: 'orderId', remote: 'id' },
    payment: { model: 'payment', local: 'paymentId', remote: 'id' },
  },
  dispute: {
    order: { model: 'order', local: 'orderId', remote: 'id' },
    filer: { model: 'user', local: 'filedBy', remote: 'id' },
  },
  escrowHold: {
    order: { model: 'order', local: 'orderId', remote: 'id' },
    payment: { model: 'payment', local: 'paymentId', remote: 'id' },
  },
  shippingQuote: {
    order: { model: 'order', local: 'orderId', remote: 'id' },
    seller: { model: 'sellerProfile', local: 'sellerId', remote: 'id' },
  },
  payment: { order: { model: 'order', local: 'orderId', remote: 'id' } },
  withdrawal: { seller: { model: 'sellerProfile', local: 'sellerId', remote: 'id' } },
  referral: { referrer: { model: 'user', local: 'referrerId', remote: 'id' } },
};

// ---------------------------- value helpers ------------------------------

function toStoreMoney(v) {
  if (v == null) return 0;
  if (typeof v === 'bigint') return Number(v);
  return Number(v);
}

function fromStoreMoney(v) {
  return BigInt(Math.round(Number(v == null ? 0 : v)));
}

function fromStoreDate(v) {
  if (v == null) return null;
  if (typeof v.toDate === 'function') return v.toDate();
  if (v instanceof Date) return v;
  return v;
}

function toNum(v) {
  if (v instanceof Date) return v.getTime();
  if (v && typeof v.toDate === 'function') return v.toDate().getTime();
  if (typeof v === 'bigint') return Number(v);
  if (typeof v === 'number') return v;
  if (typeof v === 'string' && v !== '' && !Number.isNaN(Number(v))) return Number(v);
  return NaN;
}

function eqV(a, b) {
  const na = toNum(a);
  const nb = toNum(b);
  if (!Number.isNaN(na) && !Number.isNaN(nb) &&
      (typeof a === 'number' || typeof b === 'number' || a instanceof Date || b instanceof Date ||
       (a && typeof a.toDate === 'function') || (b && typeof b.toDate === 'function') ||
       typeof a === 'bigint' || typeof b === 'bigint')) return na === nb;
  return a === b;
}

function matchField(actual, cond) {
  if (cond === null || cond === undefined) return actual == null;
  if (typeof cond === 'string' || typeof cond === 'boolean' || typeof cond === 'number' ||
      typeof cond === 'bigint' || cond instanceof Date) return eqV(actual, cond);
  if (Array.isArray(cond)) return cond.some((c) => matchField(actual, c));
  if (typeof cond !== 'object' || Object.keys(cond).length === 0) return true;
  if ('equals' in cond) return eqV(actual, cond.equals);
  if ('in' in cond) return (cond.in || []).some((v) => eqV(actual, v));
  if ('not' in cond) {
    const c = cond.not;
    if (c && typeof c === 'object') return !matchField(actual, { equals: c.equals });
    return !eqV(actual, c);
  }
  if ('contains' in cond) {
    const hay = actual == null ? '' : String(actual);
    const needle = String(cond.contains);
    return cond.mode === 'insensitive'
      ? hay.toLowerCase().includes(needle.toLowerCase())
      : hay.includes(needle);
  }
  if ('startsWith' in cond) {
    const hay = actual == null ? '' : String(actual);
    const needle = String(cond.startsWith);
    return cond.mode === 'insensitive'
      ? hay.toLowerCase().startsWith(needle.toLowerCase())
      : hay.startsWith(needle);
  }
  for (const op of ['gt', 'gte', 'lt', 'lte']) {
    if (op in cond) {
      const na = toNum(actual);
      const nb = toNum(cond[op]);
      if (Number.isNaN(na) || Number.isNaN(nb)) return false;
      if (op === 'gt' && !(na > nb)) return false;
      if (op === 'gte' && !(na >= nb)) return false;
      if (op === 'lt' && !(na < nb)) return false;
      if (op === 'lte' && !(na <= nb)) return false;
    }
  }
  return true;
}

// `where` uses Prisma's JSON form. Relation-object clauses ({ seller: {...} })
// are resolved by groupBy/findMany callers that need them and ignored here.
function matchWhere(row, where) {
  if (!where) return true;
  if (Array.isArray(where)) return where.some((w) => matchWhere(row, w));
  if (where.OR) return where.OR.some((w) => matchWhere(row, w));
  if (where.AND) return where.AND.every((w) => matchWhere(row, w));
  return Object.entries(where).every(([k, cond]) => matchField(row[k], cond));
}

function cmpV(a, b) {
  const aNull = a == null;
  const bNull = b == null;
  if (aNull && bNull) return 0;
  if (aNull) return 1;
  if (bNull) return -1;
  const na = toNum(a);
  const nb = toNum(b);
  if (!Number.isNaN(na) && !Number.isNaN(nb) &&
      (a instanceof Date || b instanceof Date || (a && typeof a.toDate === 'function') ||
       (b && typeof b.toDate === 'function') || typeof a === 'number' || typeof b === 'number' ||
       typeof a === 'bigint' || typeof b === 'bigint')) return na < nb ? -1 : na > nb ? 1 : 0;
  return a < b ? -1 : a > b ? 1 : 0;
}

function normOrderBy(spec) {
  if (!spec) return [];
  return Array.isArray(spec) ? spec : [spec];
}

// A JSON path like `{ createdAt: { path: ['meta','at'], direction: 'desc' } }`
// cannot be pushed to Firestore, so an ordered query that uses one must fall
// back to the residual scan path instead of pretending the order was applied.
function orderIsPushable(orderSpec) {
  return orderSpec.every((s) => {
    const [field, dir] = Object.entries(s)[0];
    return !(dir && typeof dir === 'object' && Array.isArray(dir.path));
  });
}

function sortRows(rows, spec) {
  if (!spec) return rows;
  const keys = normOrderBy(spec).map((s) => {
    const [field, dir] = Object.entries(s)[0];
    return { field, dir: String(dir).toLowerCase() === 'desc' ? -1 : 1 };
  });
  return [...rows].sort((a, b) => {
    for (const k of keys) {
      const d = cmpV(a[k.field], b[k.field]) * k.dir;
      if (d !== 0) return d;
    }
    return 0;
  });
}

function isRelationClause(x) {
  return x && typeof x === 'object' && !Array.isArray(x) && !(x instanceof Date) &&
    !['equals', 'in', 'not', 'contains', 'startsWith', 'gt', 'gte', 'lt', 'lte'].some((op) => op in x);
}

// Plan how much of a `where` can be pushed onto the Firestore query itself.
// Equality and single-field range operators express cleanly server-side. OR,
// `contains`, `in`, `not` and nested relation clauses cannot — they stay as a
// residual matchWhere post-filter. When the residual is empty the query is
// "exact": Firestore returns every matching doc, so the read ceiling can be the
// requested `collect` count instead of the full CAP scan.
function buildPushdownPlan(clean) {
  const filters = [];
  let residual = false;
  const rangedFields = new Set();
  // Money prices arrive as BigInt from callers but Firestore stores them as
  // numbers — coerce every pushed operand so the native where() never sees one.
  const num = (x) => (typeof x === 'bigint' ? Number(x) : x);

  for (const [k, v] of Object.entries(clean)) {
    if (v == null || isRelationClause(v)) continue;
    if (typeof v === 'string' || typeof v === 'boolean' || typeof v === 'number') {
      filters.push({ field: k, op: '==', val: v });
      continue;
    }
    if (typeof v === 'bigint') {
      filters.push({ field: k, op: '==', val: Number(v) });
      continue;
    }
    if (v instanceof Date) {
      filters.push({ field: k, op: '==', val: v });
      continue;
    }
    if (Array.isArray(v)) {
      // `in` is natively expressible. This matters most for the finance
      // sweeps, which select on `{ status: { in: [...] } }` — pushing it down
      // turns a full-collection scan into one indexed query.
      //
      // Firestore caps an `in` at 30 values and forbids combining `in` with
      // `not-in` or a range on the same field; both are handled by falling back
      // to the residual scan rather than issuing an invalid query.
      const usable =
        v.length > 0 &&
        v.length <= 30 &&
        v.every((x) =>
          x == null ? false : ['string', 'boolean', 'number', 'bigint'].includes(typeof x),
        ) &&
        !rangedFields.has(k);
      if (usable) {
        filters.push({
          field: k,
          op: 'in',
          val: v.map((x) => num(x)),
        });
        continue;
      }
      residual = true;
      continue;
    }
    if (typeof v === 'object') {
      // JSON path probes ({ path: [...], equals }) are not Firestore fields —
      // always leave them to the post-filter so behavior matches the old scan.
      if (v.path && Array.isArray(v.path)) {
        residual = true;
        continue;
      }
      const rangeOps = ['gt', 'gte', 'lt', 'lte'];
      if (v.equals != null && !(v.equals && typeof v.equals === 'object')) {
        filters.push({ field: k, op: '==', val: num(v.equals) });
        continue;
      }
      const ranges = rangeOps.filter((o) => o in v);
      if (ranges.length) {
        // Firestore allows inequality filters on one field per query; when a
        // second field needs a range, push the equalities only and post-filter.
        if (rangedFields.size === 0 || rangedFields.has(k)) {
          rangedFields.add(k);
          for (const o of ranges) {
            filters.push({ field: k, op: o === 'gt' ? '>' : o === 'gte' ? '>=' : o === 'lt' ? '<' : '<=', val: num(v[o]) });
          }
          continue;
        }
      }
    }
    residual = true;
  }

  return { filters, exact: !residual };
}

// ---------------------------- model facade -------------------------------

class ModelFacade {
  constructor(store, name) {
    this.store = store;
    this.name = name;
    this.cfg = MODELS[name];
    this.col = this.cfg.col;
    this.keyField = this.cfg.keyField || null;
    this.money = this.cfg.money || [];
  }

  db() { return this.store.db; }

  _doc(key) { return this.db().collection(this.col).doc(String(key)); }

  _docKey(key) { return `${this.col}/${key}`; }

  _overlay() { return this.store.txOverlay; }

  // Resolve a `where` to a concrete doc key when possible.
  _resolveKey(where) {
    if (!where) return null;
    if (where.id != null && (typeof where.id === 'string' || typeof where.id === 'number')) return String(where.id);
    if (this.keyField && where[this.keyField] != null &&
        (typeof where[this.keyField] === 'string' || typeof where[this.keyField] === 'number')) return String(where[this.keyField]);
    return null;
  }

  _cleanWhere(where) {
    if (!where) return where;
    const out = {};
    for (const [k, v] of Object.entries(where)) {
      if (isRelationClause(v) && RELATIONS[this.name] && RELATIONS[this.name][k]) continue;
      out[k] = v;
    }
    return out;
  }

  _serialize(data, key) {
    const row = {};
    for (const [k, v] of Object.entries(data)) {
      row[k] = this.money.includes(k) ? fromStoreMoney(v) : fromStoreDate(v);
    }
    row.id = String(key);
    return row;
  }

  _toStored(row) {
    const out = {};
    for (const [k, v] of Object.entries(row)) {
      if (k === 'id') continue;
      out[k] = this.money.includes(k) ? toStoreMoney(v) : (v instanceof Date ? v : v);
    }
    return out;
  }

  _normalizeMoney(row) {
    for (const f of this.money) {
      if (row[f] != null) row[f] = fromStoreMoney(row[f]);
    }
    return row;
  }

  async _readByKey(key) {
    const ov = this._overlay();
    if (ov) {
      const dk = this._docKey(key);
      if (ov.has(dk)) return ov.get(dk);
    }
    const snap = await this._doc(key).get();
    if (!snap.exists) return null;
    return this._serialize(snap.data(), key);
  }

/**
   * Loads rows for a query.
   *
   * Two execution strategies, neither of which can truncate:
   *
   * 1. **Pushed-down** (`plan.exact && orderBy is Firestore-expressible`).
   *    Equality filters and ordering both go to Firestore, the page is bounded
   *    by `limit`, and `startAfter` resumes without re-reading. Reads scale
   *    with page size, not collection size. Requires the composite indexes
   *    declared in firestore.indexes.json.
   *
   * 2. **Residual scan** (any operator Firestore cannot express: `in`, `not`,
   *    `contains`, JSON-path probes). Pages through the collection in bounded
   *    batches using `startAfter(documentId)` and post-filters each batch, so
   *    it stays CORRECT over any collection size while never holding more than
   *    `SCAN_PAGE_SIZE` documents in memory at once.
   *
   * The previous implementation took a third path: one `limit(1000).get()`.
   * That silently truncated every count, aggregate and ordered list past 1000
   * documents — including all six finance sweeps, which is why escrow
   * auto-release and payment expiry stopped working past that size.
   */
  async _baseRows(where, opts = {}) {
    const clean = this._cleanWhere(where);
    // Prefer a single-key resolution to a cheap doc read.
    const key = this._resolveKey(clean);
    if (key) {
      const r = await this._readByKey(key);
      const rows = r && matchWhere(r, clean) ? [r] : [];
      return this._withOverlay(rows, clean);
    }

    const plan = buildPushdownPlan(clean);
    const orderSpec = normOrderBy(opts.orderBy);
    const ordered = orderSpec.length > 0;
    const take = opts.take != null ? Number(opts.take) : null;
    const skip = Number(opts.skip || 0);

    // Pushed-down path. Ordering MUST be native: sorting an arbitrary bounded
    // page in memory would return the wrong rows, not just a truncated list.
    if (plan.exact && (!ordered || orderIsPushable(orderSpec))) {
      const rows = await this._pagedQuery({
        filters: plan.filters,
        orderBy: orderSpec,
        take: take != null ? take + skip : DEFAULT_PAGE_SIZE,
        startAfter: opts.cursor || null,
      });
      return this._withOverlay(rows, clean);
    }

    // Residual path. Without an orderBy we can stop once we have enough rows;
    // with one, the candidate set must be fully sorted, so walk it all — but in
    // bounded batches, never as a single unbounded read.
    const needAll = ordered;
    const rows = [];
    let cursor = null;
    let scanned = 0;

    for (;;) {
      const batchSize = needAll
        ? SCAN_PAGE_SIZE
        : Math.max(SCAN_PAGE_SIZE, (take || 0) + skip);
      let q = this.db().collection(this.col);
      for (const f of plan.filters) q = q.where(f.field, f.op, f.val);
      if (cursor) q = q.startAfter(cursor);

      const snap = await q.limit(batchSize).get();
      if (snap.empty) break;

      for (const d of snap.docs) {
        const row = this._serialize(d.data(), d.id);
        scanned += 1;
        if (matchWhere(row, clean)) rows.push(row);
      }

      cursor = snap.docs[snap.docs.length - 1];
      if (snap.docs.length < batchSize) break;
      if (!needAll && rows.length >= (take || 0) + skip) break;
    }

    void scanned;
    return this._withOverlay(rows, clean);
  }

  /** Merges buffered-transaction writes over a query result. */
  _withOverlay(rows, clean) {
    const ov = this._overlay();
    if (!ov) return rows;
    const map = new Map(rows.map((r) => [this._docKey(r.id), r]));
    for (const [dk, row] of ov) {
      if (!dk.startsWith(this.col + '/')) continue;
      if (row === null) map.delete(dk);
      else map.set(dk, row);
    }
    return [...map.values()].filter((r) => matchWhere(r, clean));
  }

  /**
   * One bounded, ordered Firestore page.
   *
   * Reached only when `orderBy` names real Firestore fields, so `orderBy` can
   * be pushed to the server. `limit` bounds the read; `startAfter` makes paging
   * cost O(page) instead of O(offset).
   */
  async _pagedQuery({ filters, orderBy, take, startAfter }) {
    let q = this.db().collection(this.col);
    for (const f of filters) q = q.where(f.field, f.op, f.val);
    for (const spec of orderBy) {
      const [field, dir] = Object.entries(spec)[0];
      q = q.orderBy(field, String(dir).toLowerCase() === 'desc' ? 'desc' : 'asc');
    }
    if (startAfter) {
      for (const spec of orderBy) {
        const [field] = Object.entries(spec)[0];
        q = q.startAfter(startAfter[field]);
      }
    }
    const limit = Math.min(Math.max(1, Number(take) || DEFAULT_PAGE_SIZE), HARD_PAGE_CAP);
    const snap = await q.limit(limit).get();
    return snap.docs.map((d) => this._serialize(d.data(), d.id));
  }

  /**
   * Opaque pagination cursor: the ordered field values of the last row.
   *
   * Timestamps are encoded as millis because Firestore `Timestamp` objects do
   * not survive `JSON.stringify`, which would make every cursor undecodable the
   * first time an ordered field was a date — i.e. nearly every list endpoint.
   */
  _encodeCursor(orderBy, lastRow) {
    if (!orderBy.length || !lastRow) return null;
    const payload = {};
    for (const spec of orderBy) {
      const [field] = Object.entries(spec)[0];
      const v = lastRow[field];
      if (v == null) return null;
      payload[field] =
        v && typeof v === 'object' && typeof v.toMillis === 'function'
          ? { __ts: v.toMillis() }
          : v;
    }
    return Buffer.from(JSON.stringify(payload), 'utf8').toString('base64');
  }

  _decodeCursor(cursor) {
    try {
      const parsed = JSON.parse(
        Buffer.from(String(cursor), 'base64').toString('utf8'),
      );
      const out = {};
      for (const [k, v] of Object.entries(parsed)) {
        out[k] = v && typeof v === 'object' && v.__ts != null
          ? new Date(Number(v.__ts))
          : v;
      }
      return out;
    } catch {
      return null;
    }
  }

  async _resolveRelationWhere(where) {
    const out = [];
    if (!where) return out;
    for (const [k, v] of Object.entries(where)) {
      const rel = RELATIONS[this.name] && RELATIONS[this.name][k];
      if (!rel || !isRelationClause(v)) continue;
      const kids = await this.store[rel.model].findMany({ where: v });
      const ids = kids.map((x) => String(x.id));
      out.push({ local: rel.local, ids });
    }
    return out;
  }

  // Buffered write (transaction) or direct write (root).
  persist(key, row) {
    const ov = this._overlay();
    if (ov) {
      const dk = this._docKey(key);
      ov.set(dk, row);
      this.store.txWrites.push({ model: this.name, key: String(key), row });
      return Promise.resolve();
    }
    return this._doc(key).set(this._toStored(row));
  }

  persistDelete(key) {
    const ov = this._overlay();
    if (ov) {
      const dk = this._docKey(key);
      ov.set(dk, null);
      this.store.txWrites.push({ model: this.name, key: String(key), row: null });
      return Promise.resolve();
    }
    return this._doc(key).delete();
  }

  async _project(row, select) {
    if (!select) return row;
    const out = { id: row.id };
    for (const [k, v] of Object.entries(select)) {
      if (v === true && k in row) out[k] = row[k];
    }
    return out;
  }

  async _decorate(row, select, include) {
    if (!row) return null;
    const out = select ? await this._project(row, select) : { ...row };
    if (!include) return out;
    // Relation loads are independent of each other — resolve concurrently so a
    // page of products doesn't pay include[media]+[seller]+[category] serially.
    const jobs = [];
    for (const [relName, specRaw] of Object.entries(include)) {
      if (!specRaw) continue;
      const def = RELATIONS[this.name] && RELATIONS[this.name][relName];
      if (!def) continue;
      const spec = specRaw === true ? {} : specRaw;
      const link = row[def.local];
      if (link == null) {
        out[relName] = def.many ? [] : null;
        continue;
      }
      jobs.push(this._loadRelation(def, link, spec).then((kids) => {
        out[relName] = def.many ? kids : (kids[0] || null);
      }));
    }
    await Promise.all(jobs);
    return out;
  }

  async _loadRelation(def, link, spec) {
    if (link == null) return def.many ? [] : [];
    const model = this.store[def.model];
    const isKey = model.keyField === def.remote || def.remote === 'id';
    let kids;
    if (def.many) {
      kids = await model.findMany({ where: { [def.remote]: link } });
    } else {
      const row = isKey
        ? await model.findUnique({ where: { id: link } })
        : await model.findFirst({ where: { [def.remote]: link } });
      kids = row ? [row] : [];
    }
    if (spec.where && typeof spec.where === 'object' && Object.keys(spec.where).length) {
      kids = kids.filter((k) => matchWhere(k, spec.where));
    }
    return Promise.all(kids.map((k) => model._decorate(k, spec.select, spec.include)));
  }

  async findUnique({ where = {}, select, include } = {}) {
    return this._decorate(await this._findBase({ where, take: 1 }), select, include);
  }

  async findFirst({ where = {}, orderBy, select, include } = {}) {
    // take:1 lets the pushed-down path issue a single `limit(1)` with native
    // ordering, instead of reading a page and sorting it in memory.
    const rows = sortRows(
      await this._baseRows(where, { take: 1, orderBy }),
      orderBy,
    );
    return this._decorate(rows[0] || null, select, include);
  }

  /**
   * Lists rows. Accepts either `skip`/`take` (offset paging, used by the admin
   * and analytics surfaces) or `cursor` (Firestore `startAfter`, used by the
   * app-facing list endpoints). `cursor` and `orderBy` must be used together.
   */
  async findMany({ where = {}, orderBy, take, skip = 0, cursor, select, include } = {}) {
    let rows = sortRows(
      await this._baseRows(where, {
        take: take != null ? Number(take) : null,
        skip: Number(skip) || 0,
        orderBy,
        cursor,
      }),
      orderBy,
    );
    const start = Number(skip) || 0;
    const end = take != null ? start + Number(take) : undefined;
    rows = rows.slice(start, end);
    return Promise.all(rows.map((r) => this._decorate(r, select, include)));
  }

  /**
   * Encodes an opaque cursor from a page of rows so a caller can request the
   * next one without the store exposing Firestore internals.
   */
  encodeCursor(rows, orderBy) {
    if (!rows || !rows.length) return null;
    return this._encodeCursor(normOrderBy(orderBy), rows[rows.length - 1]);
  }

  decodeCursor(cursor) {
    return this._decodeCursor(cursor);
  }

  async _findBase({ where, take }) {
    let rows = await this._baseRows(where, { take: take != null ? Number(take) : 1 });
    if (take != null) rows = rows.slice(0, take);
    return rows[0] || null;
  }

  /**
   * Exact document count.
   *
   * Uses Firestore's native `count()` aggregation for a fully pushable filter
   * (1 read billed, regardless of collection size). Anything Firestore cannot
   * express falls back to the paged residual scan, which is slower but no
   * longer silently caps at 1000.
   */
  async count({ where = {} } = {}) {
    const key = this._resolveKey(this._cleanWhere(where));
    if (key) return (await this._readByKey(key)) ? 1 : 0;

    const clean = this._cleanWhere(where);
    const plan = buildPushdownPlan(clean);
    // `count()` is a Firestore 3.10+ aggregation. Feature-detect it so the
    // test double (and any older SDK) degrades to the scan instead of throwing.
    let supportsCount = false;
    try {
      const probe = this.db().collection(this.col);
      supportsCount = typeof probe.count === 'function';
    } catch {
      supportsCount = false;
    }

    if (plan.exact && supportsCount) {
      try {
        let q = this.db().collection(this.col);
        for (const f of plan.filters) q = q.where(f.field, f.op, f.val);
        const agg = await q.count().get();
        const data = agg.data && agg.data();
        const n = data && typeof data.count === 'number'
          ? data.count
          : (data && data.count && typeof data.count.toNumber === 'function'
            ? data.count.toNumber()
            : null);
        if (n != null) return n;
      } catch (e) {
        // A count() query needs the same composite index as the read. If it is
        // missing, fall through to the scan rather than failing the request.
        if (!/FAILED_PRECONDITION|index/i.test(String(e && e.message))) throw e;
      }
    }
    return (await this._baseRows(where, { take: null })).length;
  }

  async create({ data = {}, select, include } = {}) {
    const cfg = this.cfg;
    const key = data[cfg.keyField] != null ? String(data[cfg.keyField]) : (data.id != null ? String(data.id) : randomUUID());
    const row = { ...data };
    this._normalizeMoney(row);
    row.id = key;
    if (row.createdAt == null) row.createdAt = new Date();
    if (row.updatedAt == null) row.updatedAt = new Date();
    await this.persist(key, row);
    return this._decorate(row, select, include);
  }

  // Applies Prisma atomic operators in `data` ({ field: { increment: n } })
  // on top of the current row; plain fields are replaced as Prisma does.
  _applyAtomic(cur, data) {
    const merged = { ...cur, ...data, id: cur.id };
    for (const [k, v] of Object.entries(data)) {
      if (v && typeof v === 'object' && typeof v.increment === 'number') {
        const base = typeof cur[k] === 'bigint' ? Number(cur[k]) : Number(cur[k] || 0);
        merged[k] = typeof cur[k] === 'bigint' ? BigInt(base + v.increment) : base + v.increment;
      } else if (v && typeof v === 'object' && typeof v.increment === 'bigint') {
        const base = typeof cur[k] === 'bigint' ? cur[k] : BigInt(Number(cur[k] || 0));
        merged[k] = base + v.increment;
      }
    }
    return merged;
  }

  async update({ where = {}, data = {}, select, include } = {}) {
    const key = this._resolveKey(where);
    const rows = await this._baseRows(where, { take: 1 });
    const cur = rows.find((r) => key == null || String(r.id) === String(key)) || rows[0] || null;
    if (!cur) return null;
    const merged = this._applyAtomic(cur, data);
    if (this.keyField && where[this.keyField] != null && merged[this.keyField] == null) merged[this.keyField] = where[this.keyField];
    this._normalizeMoney(merged);
    merged.updatedAt = new Date();
    await this.persist(cur.id, merged);
    return this._decorate(merged, select, include);
  }

  /**
   * Batched read-modify-write over every matching row.
   *
   * `data` is applied per row from the row's own current value, so a concurrent
   * writer is not clobbered by a stale snapshot the way it was when callers
   * pre-computed absolute values and wrote them wholesale. Callers that need
   * true atomicity on a money field must use `commerce-store` (real Firestore
   * transactions), not this.
   */
  async updateMany({ where = {}, data = {} } = {}) {
    const rows = await this._baseRows(where, { take: null });
    for (const r of rows) {
      const merged = this._applyAtomic(r, data);
      this._normalizeMoney(merged);
      merged.updatedAt = new Date();
      await this.persist(r.id, merged);
    }
    return { count: rows.length };
  }

  async upsert({ where = {}, create: createData = {}, update: updateData = {}, select } = {}) {
    const existing = (await this._baseRows(where, { take: 1 }))[0] || null;
    if (existing) return this.update({ where: { id: existing.id }, data: updateData, select });
    return this.create({ data: createData, select });
  }

  async delete({ where = {} } = {}) {
    const rows = await this._baseRows(where, { take: null });
    for (const r of rows) await this.persistDelete(r.id);
    return { count: rows.length };
  }

  /**
   * `_count` uses Firestore's native aggregation (1 read, any collection size).
   *
   * `_sum` cannot: Firestore has no server-side SUM. It is computed from the
   * paged residual scan, which is now COMPLETE rather than capped at 1000 — the
   * previous version read at most 1000 documents and reported a sum that was
   * silently wrong for every larger collection (reconciliation totals, admin
   * revenue, escrow held).
   */
  async aggregate({ where = {}, _sum = {}, _count = {} } = {}) {
    const res = {};
    const wantCount = Object.values(_count).some(Boolean);

    if (wantCount && !Object.values(_sum).some(Boolean)) {
      const n = await this.count({ where });
      res._count = {};
      for (const [f, flag] of Object.entries(_count)) {
        if (flag) res._count[f] = n;
      }
      return res;
    }

    const rows = await this._baseRows(where, { take: null });
    if (Object.keys(_sum).length) {
      res._sum = {};
      for (const [f, flag] of Object.entries(_sum)) {
        if (!flag) continue;
        res._sum[f] = rows.reduce((acc, r) => acc + fromStoreMoney(r[f]), 0n);
      }
    }
    if (Object.keys(_count).length) {
      res._count = {};
      for (const [f, flag] of Object.entries(_count)) {
        if (!flag) continue;
        res._count[f] = rows.length;
      }
    }
    return res;
  }

  async groupBy({ by = [], where = {}, _count = {}, _sum = {} } = {}) {
    const rows = await this._baseRows(where, { take: null });
    const relFilters = await this._resolveRelationWhere(where);
    const groups = new Map();
    for (const r of rows) {
      let pass = true;
      for (const rf of relFilters) if (!rf.ids.includes(String(r[rf.local]))) { pass = false; break; }
      if (!pass) continue;
      const gkey = by.map((f) => String(r[f] ?? '')).join('\u0001');
      let g = groups.get(gkey);
      if (!g) {
        g = {};
        for (const f of by) g[f] = r[f] == null ? null : r[f];
        g._count = {};
        for (const [f, flag] of Object.entries(_count)) if (flag) g._count[f] = 0;
        g._sum = {};
        for (const [f, flag] of Object.entries(_sum)) if (flag) g._sum[f] = 0n;
        groups.set(gkey, g);
      }
      for (const [f, flag] of Object.entries(_count)) if (flag) g._count[f] += 1;
      for (const [f, flag] of Object.entries(_sum)) if (flag) g._sum[f] += fromStoreMoney(r[f]);
    }
    return [...groups.values()];
  }
}

// ------------------------------ store root -------------------------------

class StoreRoot {
  constructor(db) {
    this.db = db;
    this.txOverlay = null;
    this.txWrites = null;
    for (const name of Object.keys(MODELS)) {
      this[name] = new ModelFacade(this, name);
    }
  }

  async $transaction(arg) {
    if (typeof arg === 'function') {
      const tx = new StoreRoot(this.db);
      tx.txOverlay = new Map();
      tx.txWrites = [];
      const result = await arg(tx);
      await tx._flush();
      return result;
    }
    if (Array.isArray(arg)) {
      const isSpecs = arg.length > 0 && arg.every((x) => x && typeof x === 'object' && 'model' in x && 'op' in x);
      if (isSpecs) {
        const tx = new StoreRoot(this.db);
        tx.txOverlay = new Map();
        tx.txWrites = [];
        const results = [];
        for (const spec of arg) {
          results.push(await tx[spec.model][spec.op](spec.args || {}));
        }
        await tx._flush();
        return results;
      }
      // Promise array (Prisma array form): awaited in order.
      const results = [];
      for (const p of arg) results.push(await p);
      return results;
    }
    throw new Error('INVALID_TRANSACTION');
  }

  // Health probe kept Prisma-shaped: resolves when the underlying db answers.
  async $queryRaw() {
    await this.db.listCollections();
    return [{ id: 1 }];
  }

  async ping() {
    await this.db.listCollections();
    return true;
  }

  async _flush() {
    // Dedupe to one write per doc; last write wins (batch.set is idempotent).
    const finalOps = new Map();
    for (const w of this.txWrites) {
      finalOps.set(w.model + '/' + w.key, w);
    }
    const batch = this.db.batch();
    for (const w of finalOps.values()) {
      const facade = this[w.model];
      const ref = this.db.collection(facade.col).doc(String(w.key));
      if (w.row === null) batch.delete(ref);
      else batch.set(ref, facade._toStored(w.row));
    }
    await batch.commit();
  }
}

// --------------------------- public surface ------------------------------

// Builder seam for hermetic tests (mirrors commerce-store's storeWith(db)):
// pass a fake Firestore db to exercise logic without credentials.
function storeWith(db) {
  return new StoreRoot(db);
}

function makeStore(db) {
  return new StoreRoot(db);
}

function getStore() {
  const db = getFirebaseFirestore();
  if (!db) throw new Error('Firestore not configured');
  return new StoreRoot(db);
}

module.exports = {
  MODELS,
  RELATIONS,
  matchWhere,
  matchField,
  toStoreMoney,
  fromStoreMoney,
  ModelFacade,
  StoreRoot,
  storeWith,
  makeStore,
  getStore,
};