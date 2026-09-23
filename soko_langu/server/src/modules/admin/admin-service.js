const { getStore } = require('../../config/database');
const { getFirebaseFirestore } = require('../../config/firebase');

// The app is Firestore-first (products, users, BuyerRequests and legacy orders
// are written straight to Firestore by the client), so Postgres-only counts
// under-report reality. getFirestoreOverlay() pulls live Firestore totals and
// the dashboard/metrics merge them so admin KPIs reflect what users actually do.
async function getFirestoreOverlay() {
  const fsDb = getFirebaseFirestore();
  if (!fsDb) return null;
  const dayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);
  try {
    const [users, usersToday, prodAll, prodActive, ordAll, ordToday, ordSnap] = await Promise.all([
      fsDb.collection('users').count().get().catch(() => null),
      fsDb.collection('users').where('createdAt', '>=', dayAgo).count().get().catch(() => null),
      fsDb.collection('products').count().get().catch(() => null),
      fsDb.collection('products').where('isActive', '==', true).count().get().catch(() => null),
      fsDb.collection('orders').count().get().catch(() => null),
      fsDb.collection('orders').where('createdAt', '>=', dayAgo).count().get().catch(() => null),
      fsDb.collection('orders').select('status').limit(2000).get().catch(() => null),
    ]);
    const ordersByStatus = {};
    if (ordSnap) ordSnap.forEach((d) => {
      const st = (d.data() && d.data().status) || 'unknown';
      ordersByStatus[st] = (ordersByStatus[st] || 0) + 1;
    });
    return {
      users: users?.data().count ?? null,
      usersToday: usersToday?.data().count ?? null,
      products: prodAll?.data().count ?? null,
      activeProducts: prodActive?.data().count ?? null,
      orders: ordAll?.data().count ?? null,
      ordersToday: ordToday?.data().count ?? null,
      ordersByStatus,
    };
  } catch (e) {
    console.error('Firestore dashboard overlay failed:', e?.message || e);
    return null;
  }
}

/**
 * Admin dashboard KPIs: revenue, orders, users, disputes, system health.
 */
async function getDashboard() {
  const store = getStore();
  const today = new Date();
  today.setHours(0, 0, 0, 0);

  const [users, newUsers, orders, completedOrders, revenue, activeDisputes, escrowHeld, products] =
    await Promise.all([
      store.user.count(),
      store.user.count({ where: { createdAt: { gte: today } } }),
      store.order.count(),
      store.order.count({ where: { status: { in: ['completed', 'wallet_credited', 'payout_pending', 'payout_complete'] } } }),
      store.order.aggregate({
        _sum: { platformCommission: true },
        where: { status: { in: ['completed', 'wallet_credited'] } },
      }),
      store.dispute.count({ where: { status: 'open' } }),
      store.escrowHold.aggregate({
        _sum: { amount: true },
        where: { status: 'holding' },
      }),
      store.product.count(),
    ]);

  const fs = await getFirestoreOverlay();

  return {
    kpis: {
      users: Math.max(users, fs?.users ?? 0),
      newUsersToday: Math.max(newUsers, fs?.usersToday ?? 0),
      orders: Math.max(orders, fs?.orders ?? 0),
      completedOrders,
      commissionRevenue: revenue._sum.platformCommission?.toString() || '0',
      activeDisputes,
      escrowHeld: escrowHeld._sum.amount?.toString() || '0',
      products: Math.max(products, fs?.products ?? 0),
      pgUsers: users,
      pgProducts: products,
      pgOrders: orders,
      fsUsers: fs?.users ?? null,
      fsUsersToday: fs?.usersToday ?? null,
      fsProducts: fs?.products ?? null,
      fsOrders: fs?.orders ?? null,
      fsOrdersToday: fs?.ordersToday ?? null,
    },
  };
}

/**
 * Search users for admin (by email, phone, username, id).
 */
async function searchUsers({ q, role, accountStatus, page = 1, limit = 20 }) {
  const store = getStore();
  const where = {
    ...(q
      ? {
          OR: [
            { email: { contains: q, mode: 'insensitive' } },
            { phone: { contains: q } },
            { username: { contains: q, mode: 'insensitive' } },
            { displayName: { contains: q, mode: 'insensitive' } },
          ],
        }
      : {}),
    ...(role ? { role } : {}),
    ...(accountStatus ? { accountStatus } : {}),
  };

  const [users, total] = await Promise.all([
    store.user.findMany({
      where,
      select: {
        id: true,
        email: true,
        phone: true,
        username: true,
        displayName: true,
        avatarUrl: true,
        role: true,
        accountStatus: true,
        firebaseUid: true,
        createdAt: true,
      },
      orderBy: { createdAt: 'desc' },
      take: Number(limit),
      skip: (Number(page) - 1) * Number(limit),
    }),
    store.user.count({ where }),
  ]);

  // Firestore rules gate client-side product writes / BuyerRequests reads on
  // users/{uid}.isSuspended (notSuspended()), which is independent of the
  // Postgres accountStatus. Surface the Firestore flag so the panel can show
  // (and from there, fix) mismatches.
  let fsByUid = {};
  try {
    const fsDb = getFirebaseFirestore();
    if (fsDb) {
      const uids = users.map((u) => u.firebaseUid).filter(Boolean);
      if (uids.length) {
        const snaps = await Promise.all(uids.map((uid) => fsDb.collection('users').doc(uid).get().catch(() => null)));
        snaps.forEach((s) => {
          if (s && s.exists) fsByUid[s.id] = s.data() || {};
        });
      }
    }
  } catch (e) {
    console.error('Firestore user flag fetch failed:', e?.message || e);
  }

  const pgRows = users.map((u) => ({
    ...u,
    firebaseUid: u.firebaseUid || null,
    firestoreSuspended:
      u.firebaseUid && fsByUid[u.firebaseUid] ? fsByUid[u.firebaseUid].isSuspended === true : null,
    src: 'pg',
  }));

  // Merge Firestore-only accounts (PG has no row for them) so the Watumiaji
  // tab reflects everyone, not just the Postgres subset.
  let fsRows = [];
  try {
    const fsDb = getFirebaseFirestore();
    if (fsDb) {
      const pgUids = new Set(
        (await store.user.findMany({ where: { firebaseUid: { not: null } }, select: { firebaseUid: true } }))
          .map((u) => u.firebaseUid).filter(Boolean)
      );
      const snap = await fsDb.collection('users').orderBy('createdAt', 'desc').limit(250).get().catch(() => null);
      if (snap) {
        snap.forEach((doc) => {
          if (pgUids.has(doc.id)) return;
          const d = doc.data() || {};
          const displayName = d.displayName || d.username || d.name || '';
          const email = String(d.email || '');
          const phone = String(d.phone || '');
          const username = String(d.username || '');
          const rowRole = d.isAdmin === true ? 'admin' : String(d.role || 'buyer');
          const rowStatus = d.isSuspended === true ? 'suspended' : 'active';
          if (q) {
            const needle = String(q).toLowerCase();
            if (![email, phone, username, displayName].some((v) => v.toLowerCase().includes(needle))) return;
          }
          if (role && rowRole !== role) return;
          if (accountStatus && rowStatus !== accountStatus) return;
          const rawTs = d.createdAt;
          let createdAt = rawTs;
          if (rawTs && rawTs.toDate) createdAt = rawTs.toDate();
          else if (rawTs && rawTs.seconds != null) createdAt = new Date(Number(rawTs.seconds) * 1000);
          fsRows.push({
            id: doc.id,
            firebaseUid: doc.id,
            email: email || null,
            phone: phone || null,
            username: username || null,
            displayName: displayName || null,
            avatarUrl: d.avatarUrl || null,
            role: rowRole,
            accountStatus: rowStatus,
            firestoreSuspended: d.isSuspended === true,
            createdAt,
            src: 'fs',
          });
        });
      }
    }
  } catch (e) {
    console.error('Firestore user merge failed:', e?.message || e);
  }

  const merged = [...pgRows, ...fsRows].sort(
    (a, b) => new Date(b.createdAt || 0) - new Date(a.createdAt || 0)
  );
  const start = (Number(page) - 1) * Number(limit);
  const pgTotal = Number(total);
  const grandTotal = fsRows.length ? pgTotal + fsRows.length : pgTotal;

  return {
    users: merged.slice(start, start + Number(limit)),
    pagination: { page: Number(page), limit: Number(limit), total: grandTotal },
  };
}

/**
 * Get all transactions/ledger for admin financial module.
 */
async function listLedger({ type, page = 1, limit = 50 }) {
  const store = getStore();
  const where = type ? { type } : {};
  const [entries, total] = await Promise.all([
    store.walletLedgerEntry.findMany({
      where,
      include: { wallet: { include: { seller: true } } },
      orderBy: { createdAt: 'desc' },
      take: Number(limit),
      skip: (Number(page) - 1) * Number(limit),
    }),
    store.walletLedgerEntry.count({ where }),
  ]);
  return { entries, pagination: { page: Number(page), limit: Number(limit), total } };
}

async function listAuditLogs({ action, entityType, actorId, page = 1, limit = 50 }) {
  const store = getStore();
  const where = {};
  if (action) where.action = action;
  if (entityType) where.entityType = entityType;
  if (actorId) where.actorId = actorId;
  const [entries, total] = await Promise.all([
    store.auditLog.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      take: Number(limit),
      skip: (Number(page) - 1) * Number(limit),
    }),
    store.auditLog.count({ where }),
  ]);
  return { entries, pagination: { page: Number(page), limit: Number(limit), total } };
}

async function getMetrics() {
  const store = getStore();
  const [
    userCount,
    orderStatusGroups,
    paymentStatusGroups,
    withdrawalsPending,
    disputesOpen,
    escrowHolding,
  ] = await Promise.all([
    store.user.count(),
    store.order.groupBy({ by: ['status'], _count: { status: true }, _sum: { totalAmount: true } }),
    store.payment.groupBy({ by: ['status'], _count: { status: true }, _sum: { amount: true } }),
    store.withdrawal.count({ where: { status: { in: ['pending', 'processing'] } } }),
    store.dispute.count({ where: { status: { in: ['open', 'under_review'] } } }),
    store.escrowHold.aggregate({ _sum: { amount: true }, _count: true }),
  ]);
  const gmv = orderStatusGroups
    .filter((g) => !['cancelled', 'refunded'].includes(g.status))
    .reduce((sum, g) => sum + Number(g._sum.totalAmount || 0), 0);
  let ordersByStatus = orderStatusGroups.map((g) => ({
    status: g.status,
    count: g._count.status,
    totalAmount: Number(g._sum.totalAmount || 0).toString(),
  }));
  const fs = await getFirestoreOverlay();
  if (fs && fs.ordersByStatus && Object.keys(fs.ordersByStatus).length) {
    for (const [st, count] of Object.entries(fs.ordersByStatus)) {
      const ex = ordersByStatus.find((g) => (g.status || '').toLowerCase() === String(st).toLowerCase());
      if (ex) ex.count += count;
      else ordersByStatus.push({ status: st, count, totalAmount: '0' });
    }
  }
  return {
    users: Math.max(userCount, fs?.users ?? 0),
    gmv,
    ordersByStatus,
    paymentsByStatus: paymentStatusGroups.map((g) => ({
      status: g.status,
      count: g._count.status,
      totalAmount: Number(g._sum.amount || 0).toString(),
    })),
    withdrawalsPending,
    disputesOpen,
    escrowHolding: {
      count: escrowHolding._count,
      totalAmount: Number(escrowHolding._sum.amount || 0).toString(),
    },
  };
}

module.exports = { getDashboard, searchUsers, listLedger, listAuditLogs, getMetrics };
