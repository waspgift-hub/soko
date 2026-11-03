// Lightweight usage analytics for the admin panel (DAU/WAU/MAU/YAU,
// requests per min/hour/day/month/year, per-user request counts).
//
// Design: Redis counters only — no schema migration, no per-request DB
// writes. EVERYTHING here is fire-and-forget: analytics must never slow or
// break traffic, so all writes skip silently when Redis is unreachable and
// all reads degrade to empty data.
//
// Keys (prefix sv:act:, UTC buckets):
//   req:min:YYYYMMDDHHmm  (EX 3h)      req:hour:YYYYMMDDHH (EX 72h)
//   req:day:YYYYMMDD      (EX 400d)    req:month:YYYYMM    (EX 800d)
//   req:year:YYYY         (no expiry)
//   dau:YYYYMMDD          HyperLogLog of user ids (EX 400d)
//   users:YYYYMMDD        hash uid -> request count (EX 400d)
//   login:UID             throttle flag so lastLoginAt updates hourly (EX 1h)
const { getRedis } = require('../config/redis');
const { getPrisma } = require('../config/database');

const P = 'sv:act:';
const HOUR = 3600;
const DAY = 86400;

let redisReady = false;
let listenersOn = false;

// The shared client reconnects in the background; only write when it has
// signalled ready, otherwise commands would pile up in the offline queue.
function client() {
  try {
    const r = getRedis();
    if (r && !listenersOn) {
      listenersOn = true;
      r.on('ready', () => { redisReady = true; });
      r.on('close', () => { redisReady = false; });
      r.on('end', () => { redisReady = false; });
      // The client may have connected before our listeners attached.
      if (r.status === 'ready') redisReady = true;
    }
    return redisReady ? r : null;
  } catch (_) {
    return null;
  }
}

// One-time backfill: seed lastLoginAt from the Firestore user_sessions
// mirror so active-user counts are meaningful even for accounts created
// before per-request tracking existed. Runs once per process, only when
// there are users with no login timestamp at all.
let backfillDone = false;
async function backfillLastLogin() {
  if (backfillDone) return;
  backfillDone = true;
  try {
    const prisma = getPrisma();
    if (!prisma) return;
    const nullCount = await prisma.user.count({ where: { lastLoginAt: null } });
    if (!nullCount) return;
    const { getFirebaseFirestore } = require('../config/firebase');
    const db = getFirebaseFirestore();
    if (!db) return;
    const snap = await db.collection('user_sessions').get();
    const ops = [];
    const flush = async () => { const batch = ops.splice(0); if (batch.length) await Promise.all(batch); };
    for (const doc of snap.docs.slice(0, 5000)) {
      const d = doc.data() || {};
      const ts = d.lastActive;
      const at = ts ? (ts.toDate ? ts.toDate() : new Date(ts)) : null;
      if (!at || isNaN(at.getTime())) continue;
      ops.push(
        prisma.user.updateMany({
          where: { firebaseUid: doc.id, OR: [{ lastLoginAt: null }, { lastLoginAt: { lt: at } }] },
          data: { lastLoginAt: at },
        }).catch(() => {})
      );
      if (ops.length >= 200) await flush();
    }
    await flush();
  } catch (_) {}
}

function fire(promise) {
  if (promise && typeof promise.catch === 'function') promise.catch(() => {});
}

function buckets(now = new Date()) {
  const iso = now.toISOString();
  const digits = iso.replace(/\D/g, ''); // YYYYMMDDHHmmssmmm
  return {
    min: digits.slice(0, 12),
    hour: digits.slice(0, 10),
    day: digits.slice(0, 8),
    month: digits.slice(0, 6),
    year: digits.slice(0, 4),
  };
}

// Global counters for every /api hit (authenticated or not).
function recordApiHit() {
  const r = client();
  if (!r) return;
  try {
    const b = buckets();
    const p = r.pipeline();
    p.incr(P + 'req:min:' + b.min); p.expire(P + 'req:min:' + b.min, 3 * HOUR);
    p.incr(P + 'req:hour:' + b.hour); p.expire(P + 'req:hour:' + b.hour, 3 * DAY);
    p.incr(P + 'req:day:' + b.day); p.expire(P + 'req:day:' + b.day, 400 * DAY);
    p.incr(P + 'req:month:' + b.month); p.expire(P + 'req:month:' + b.month, 800 * DAY);
    p.incr(P + 'req:year:' + b.year);
    fire(p.exec());
  } catch (_) {}
}

// Per-user activity for an authenticated request: distinct-user HyperLogLog,
// per-day request hash, and an hourly-throttled lastLoginAt touch so the
// Postgres active-user counts stay fresh for every login method.
function recordUserActivity(uid) {
  if (!uid) return;
  const r = client();
  if (!r) return;
  try {
    const id = String(uid);
    const day = buckets().day;
    const p = r.pipeline();
    p.pfadd(P + 'dau:' + day, id);
    p.expire(P + 'dau:' + day, 400 * DAY);
    p.hincrby(P + 'users:' + day, id, 1);
    p.expire(P + 'users:' + day, 400 * DAY);
    p.set(P + 'login:' + id, '1', 'EX', HOUR, 'NX');
    fire(p.exec().then((res) => {
      try {
        const setRes = res && res[4];
        if (setRes && setRes[1] === 'OK') {
          const prisma = getPrisma();
          if (prisma) fire(prisma.user.update({ where: { id }, data: { lastLoginAt: new Date() } }));
        }
      } catch (_) {}
    }));
  } catch (_) {}
}

// ---- Reads (awaited; always resolve, never throw) ----

// Active users from lastLoginAt (rolling windows, works historically).
async function getActiveStats() {
  const fallback = { day: 0, week: 0, month: 0, year: 0, totalUsers: 0, series14: [] };
  try {
    const prisma = getPrisma();
    if (!prisma) return fallback;
    await backfillLastLogin();
    const now = Date.now();
    const cut = (ms) => new Date(now - ms);
    const [day, week, month, year, totalUsers] = await Promise.all([
      prisma.user.count({ where: { lastLoginAt: { gte: cut(24 * HOUR * 1000) } } }),
      prisma.user.count({ where: { lastLoginAt: { gte: cut(7 * DAY * 1000) } } }),
      prisma.user.count({ where: { lastLoginAt: { gte: cut(30 * DAY * 1000) } } }),
      prisma.user.count({ where: { lastLoginAt: { gte: cut(365 * DAY * 1000) } } }),
      prisma.user.count(),
    ]);
    let series14 = [];
    try {
      const rows = await prisma.$queryRaw`
        SELECT TO_CHAR(DATE(last_login_at), 'YYYY-MM-DD') AS date, COUNT(*)::int AS users
        FROM users WHERE last_login_at >= ${cut(14 * DAY * 1000)}
        GROUP BY 1 ORDER BY 1`;
      series14 = (rows || []).map((r) => ({ date: String(r.date), users: Number(r.users) || 0 }));
    } catch (_) {}
    return { day, week, month, year, totalUsers, series14 };
  } catch (_) {
    return fallback;
  }
}

function pad(n, len) {
  let s = String(n);
  while (s.length < len) s = '0' + s;
  return s;
}

// Request totals per bucket + distinct actives + avg per active user.
// Windows: min -> last 60 min, hour -> last 24h, day -> last 30d,
// month -> last 12 months, year -> last 5 years.
async function getRequestSeries(granularity) {
  const empty = { granularity, points: [], spanTotal: 0, spanActives: 0, perUserAvg: 0, tracked: false };
  try {
    const r = client();
    if (!r) return empty;
    const now = new Date();
    const specs = {
      min: { n: 60, stepMs: 60 * 1000, key: (d) => P + 'req:min:' + ts(d).slice(0, 12), label: (d) => labelHM(d) },
      hour: { n: 24, stepMs: HOUR * 1000, key: (d) => P + 'req:hour:' + ts(d).slice(0, 10), label: (d) => labelHM(d) },
      day: { n: 30, stepMs: DAY * 1000, key: (d) => P + 'req:day:' + ts(d).slice(0, 8), label: (d) => labelMD(d) },
      month: { n: 12, stepMs: 0, key: (d) => P + 'req:month:' + ts(d).slice(0, 6), label: (d) => labelYM(d) },
      year: { n: 5, stepMs: 0, key: (d) => P + 'req:year:' + ts(d).slice(0, 4), label: (d) => ts(d).slice(0, 4) },
    };
    const spec = specs[granularity] || specs.day;
    const times = [];
    if (granularity === 'month') {
      for (let i = spec.n - 1; i >= 0; i--) times.push(new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - i, 1)));
    } else if (granularity === 'year') {
      for (let i = spec.n - 1; i >= 0; i--) times.push(new Date(Date.UTC(now.getUTCFullYear() - i, 0, 1)));
    } else {
      for (let i = spec.n - 1; i >= 0; i--) times.push(new Date(now.getTime() - i * spec.stepMs));
    }
    const keys = times.map(spec.key);
    const vals = await r.mget(keys);
    const points = times.map((t, i) => ({ t: spec.label(t), total: Number(vals[i]) || 0 }));
    const spanTotal = points.reduce((a, p) => a + p.total, 0);
    // Distinct actives over the span: union the daily HLLs it touches.
    const daySet = new Set();
    if (granularity === 'min' || granularity === 'hour') {
      daySet.add(P + 'dau:' + ts(now).slice(0, 8));
    } else if (granularity === 'day') {
      times.forEach((t) => daySet.add(P + 'dau:' + ts(t).slice(0, 8)));
    } else if (granularity === 'month') {
      const start = times[0].getTime();
      for (let d = new Date(start); d <= now; d = new Date(d.getTime() + DAY * 1000)) daySet.add(P + 'dau:' + ts(d).slice(0, 8));
    } else {
      for (let i = 0; i < 365 * spec.n; i += 7) daySet.add(P + 'dau:' + ts(new Date(now.getTime() - i * DAY * 1000)).slice(0, 8));
    }
    let spanActives = 0;
    try {
      const ks = [...daySet];
      if (ks.length) spanActives = Number(await r.pfcount(...ks)) || 0;
    } catch (_) {}
    return {
      granularity,
      points,
      spanTotal,
      spanActives,
      perUserAvg: spanActives ? Math.round((spanTotal / spanActives) * 10) / 10 : 0,
      tracked: true,
    };
  } catch (_) {
    return empty;
  }
}

function ts(d) { return d.toISOString().replace(/\D/g, ''); }
function labelHM(d) { return pad(d.getUTCHours(), 2) + ':' + pad(d.getUTCMinutes(), 2); }
function labelMD(d) { return pad(d.getUTCDate(), 2) + '/' + pad(d.getUTCMonth() + 1, 2); }
function labelYM(d) { return d.getUTCFullYear() + '-' + pad(d.getUTCMonth() + 1, 2); }

// Top users by request count over the last N days, enriched from Postgres.
async function getTopUsers(days, limit) {
  try {
    const r = client();
    if (!r) return { users: [], days, tracked: false };
    const now = Date.now();
    const perDay = [];
    for (let i = 0; i < days; i++) {
      const day = ts(new Date(now - i * DAY * 1000)).slice(0, 8);
      perDay.push(r.hgetall(P + 'users:' + day).catch(() => ({})));
    }
    const maps = await Promise.all(perDay);
    const totals = new Map();
    for (const m of maps) {
      for (const uid of Object.keys(m || {})) {
        totals.set(uid, (totals.get(uid) || 0) + (Number(m[uid]) || 0));
      }
    }
    const ranked = [...totals.entries()].sort((a, b) => b[1] - a[1]).slice(0, limit);
    if (!ranked.length) return { users: [], days, tracked: true };
    const prisma = getPrisma();
    let profiles = [];
    try {
      profiles = await prisma.user.findMany({
        where: { id: { in: ranked.map((x) => x[0]) } },
        select: { id: true, email: true, phone: true, displayName: true, role: true, lastLoginAt: true },
      });
    } catch (_) {}
    const byId = new Map((profiles || []).map((u) => [u.id, u]));
    return {
      users: ranked.map(([uid, requests], i) => {
        const u = byId.get(uid) || {};
        return {
          rank: i + 1,
          userId: uid,
          email: u.email || null,
          phone: u.phone || null,
          displayName: u.displayName || null,
          role: u.role || null,
          requests,
          avgPerDay: Math.round((requests / days) * 10) / 10,
          lastLoginAt: u.lastLoginAt || null,
        };
      }),
      days,
      tracked: true,
    };
  } catch (_) {
    return { users: [], days, tracked: false };
  }
}

module.exports = { recordApiHit, recordUserActivity, getActiveStats, getRequestSeries, getTopUsers };
