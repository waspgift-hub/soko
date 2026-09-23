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

const CAP = 1000;

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
  sponsoredCampaign: { col: 'sponsoredCampaigns', money: ['bidAmountTzs', 'dailyBudgetTzs', 'totalBudgetTzs', 'spendTzs'] },
  campaignPlacement: { col: 'campaignPlacements' },
  campaignEvent: { col: 'campaignEvents' },
  campaignImpression: { col: 'campaignImpressions' },
  campaignClick: { col: 'campaignClicks' },
  campaignAttribution: { col: 'campaignAttributions' },
  campaignPayment: { col: 'campaignPayments' },
  campaignAuditLog: { col: 'campaignAuditLogs' },
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
  sponsoredCampaign: { seller: { model: 'sellerProfile', local: 'sellerId', remote: 'id' } },
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

  async _baseRows(where) {
    const clean = this._cleanWhere(where);
    // Prefer a single-key resolution to a cheap doc read.
    const key = this._resolveKey(clean);
    let rows = [];
    if (key) {
      const r = await this._readByKey(key);
      if (r && matchWhere(r, clean)) rows.push(r);
    } else {
      // Push down one equality filter; range/`in`/contains post-filtered.
      let primer = null;
      for (const [k, v] of Object.entries(clean)) {
        if (isRelationClause(v)) continue;
        if (k === 'id' || k === this.keyField) continue;
        if (typeof v === 'string' || typeof v === 'boolean' || typeof v === 'number' ||
            (typeof v === 'bigint' && (typeof v === 'bigint'))) {
          primer = { field: k, value: typeof v === 'bigint' ? Number(v) : v };
          break;
        }
      }
      let q = this.db().collection(this.col);
      if (primer) q = q.where(primer.field, '==', primer.value);
      const snap = await q.limit(CAP).get();
      for (const d of snap.docs) {
        const row = this._serialize(d.data(), d.id);
        if (matchWhere(row, clean)) rows.push(row);
      }
    }
    const ov = this._overlay();
    if (ov) {
      const map = new Map(rows.map((r) => [this._docKey(r.id), r]));
      for (const [dk, row] of ov) {
        if (!dk.startsWith(this.col + '/')) continue;
        if (row === null) map.delete(dk);
        else map.set(dk, row);
      }
      rows = [...map.values()].filter((r) => matchWhere(r, clean));
    }
    return rows;
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
    for (const [relName, specRaw] of Object.entries(include)) {
      if (!specRaw) continue;
      const def = RELATIONS[this.name] && RELATIONS[this.name][relName];
      if (!def) continue;
      const spec = specRaw === true ? {} : specRaw;
      const link = row[def.local];
      const kids = await this._loadRelation(def, link, spec);
      out[relName] = def.many ? kids : (kids[0] || null);
    }
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
    const decorated = [];
    for (const k of kids) decorated.push(await model._decorate(k, spec.select, spec.include));
    return decorated;
  }

  async findUnique({ where = {}, select, include } = {}) {
    return this._decorate(await this._findBase({ where, take: 1 }), select, include);
  }

  async findFirst({ where = {}, orderBy, select, include } = {}) {
    const rows = sortRows(await this._baseRows(where), orderBy);
    return this._decorate(rows[0] || null, select, include);
  }

  async findMany({ where = {}, orderBy, take, skip = 0, select, include } = {}) {
    let rows = sortRows(await this._baseRows(where), orderBy);
    const start = Number(skip) || 0;
    const end = take != null ? start + Number(take) : undefined;
    rows = rows.slice(start, end);
    const out = [];
    for (const r of rows) out.push(await this._decorate(r, select, include));
    return out;
  }

  async _findBase({ where, take }) {
    let rows = await this._baseRows(where);
    if (take != null) rows = rows.slice(0, take);
    return rows[0] || null;
  }

  async count({ where = {} } = {}) {
    return (await this._baseRows(where)).length;
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
    const rows = key != null ? await this._baseRows({ ...where }) : await this._baseRows(where);
    const cur = rows.find((r) => key == null || String(r.id) === String(key)) || rows[0] || null;
    if (!cur) return null;
    const merged = this._applyAtomic(cur, data);
    if (this.keyField && where[this.keyField] != null && merged[this.keyField] == null) merged[this.keyField] = where[this.keyField];
    this._normalizeMoney(merged);
    merged.updatedAt = new Date();
    await this.persist(cur.id, merged);
    return this._decorate(merged, select, include);
  }

  async updateMany({ where = {}, data = {} } = {}) {
    const rows = await this._baseRows(where);
    for (const r of rows) {
      const merged = this._applyAtomic(r, data);
      this._normalizeMoney(merged);
      merged.updatedAt = new Date();
      await this.persist(r.id, merged);
    }
    return { count: rows.length };
  }

  async upsert({ where = {}, create: createData = {}, update: updateData = {}, select } = {}) {
    const existing = (await this._baseRows(where))[0] || null;
    if (existing) return this.update({ where: { id: existing.id }, data: updateData, select });
    return this.create({ data: createData, select });
  }

  async delete({ where = {} } = {}) {
    const rows = await this._baseRows(where);
    for (const r of rows) await this.persistDelete(r.id);
    return { count: rows.length };
  }

  async aggregate({ where = {}, _sum = {}, _count = {} } = {}) {
    const rows = await this._baseRows(where);
    const res = {};
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
    const rows = await this._baseRows(where);
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