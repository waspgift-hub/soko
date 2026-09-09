// Compat admin router: verbatim port of the proven old-server /api/admin
// handlers (stats, analytics, users, products, orders, transactions,
// withdrawals, KYC, finance, audit). Firestore is the same project, so the
// browser admin panel keeps working with zero client changes. Admin gating
// mirrors the old semantics: x-admin-secret OR Firebase admin (isAdmin flag).
const express = require('express');
const admin = require('firebase-admin');
const { getFirebaseFirestore } = require('../../config/firebase');
const { requireAdmin } = require('./auth-helpers');
const { sendOneSignalNotification } = require('./notify');
const {
  clickpesaBalance,
  clickpesaRawBalances,
  clickpesaQueryPayments,
  clickpesaQueryPayouts,
} = require('../../../clickpesa');

const PLATFORM_COMMISSION_PERCENT = 0.035; // 3.5% platform commission
const AD_REVENUE_PER_VIEW = 15;            // TZS per ad view (estimate only)
const PAYED_STATUSES = new Set([
  'escrow_hold',
  'paid_escrow_hold',
  'paid_escrow_held',
  'dispatched',
  'delivered',
  'delivery_confirmed',
  'confirmed',
  'completed',
  'refunded',
]);

const db = getFirebaseFirestore();

// In-memory TTL cache for the heavy aggregation endpoints. These aggregate
// full Firestore collections (users, transactions, revenue_transactions) on
// every request, which made the panel idle 3–7s on a blank page. 30–60s
// staleness is fine for a super-admin overview; every admin write clears it.
const mem = { cache: {} };
async function memGet(key, ttlMs, loader) {
  const hit = mem.cache[key];
  if (hit && Date.now() - hit.at < ttlMs) return hit.value;
  const value = await loader();
  mem.cache[key] = { at: Date.now(), value };
  return value;
}
function clearAdminCache() {
  mem.cache = {};
}

async function updateSellerKycOnProducts(sellerId, kycApproved) {
  if (!db || !sellerId) return;
  try {
    const productsSnap = await db.collection('products').where('sellerId', '==', sellerId).get();
    const batch = db.batch();
    let count = 0;
    productsSnap.docs.forEach((doc) => {
      batch.update(doc.ref, { sellerKycApproved: kycApproved });
      count++;
    });
    if (count > 0) await batch.commit();
  } catch (e) {
    console.error(`Failed to update sellerKycApproved for ${sellerId}:`, e);
  }
}

async function auditLog(entry) {
  await db.collection('audit_log').add({
    userId: entry.userId || null,
    type: entry.type || 'admin_action',
    amount: entry.amount || 0,
    reason: entry.reason || '',
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
  });
}

const router = express.Router();

async function adminGate(req, res) {
  const auth = await requireAdmin(req, res);
  return auth.ok;
}

// ---- Dashboard KPIs ----
router.get('/stats', async (req, res) => {
  try {
    if (!(await adminGate(req, res))) return;
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const result = await memGet('admin.stats', 30_000, async () => {
      const [usersSnap, ordersSnap, withdrawalsSnap, adViewsSnap] = await Promise.all([
        db.collection('users').count().get(),
        db.collection('orders').count().get(),
        db.collection('withdrawals').count().get(),
        db.collection('ad_views').count().get(),
      ]);

      const balanceSnap = await db.collection('users').get();
      let totalSellerBalance = 0;
      balanceSnap.docs.forEach((doc) => {
        const d = doc.data();
        totalSellerBalance += d.sellerBalance || 0;
      });

      return {
        totalUsers: usersSnap.data().count,
        totalOrders: ordersSnap.data().count,
        totalWithdrawals: withdrawalsSnap.data().count,
        totalAdViews: adViewsSnap.data().count,
        totalSellerBalance,
      };
    });

    res.json(result);
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ---- Transactions list ----
router.get('/transactions', async (req, res) => {
  try {
    if (!(await adminGate(req, res))) return;
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const limit = Math.min(parseInt(req.query.limit) || 100, 500);
    const snap = await db.collection('transactions').orderBy('createdAt', 'desc').limit(limit).get();
    const transactions = snap.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
    res.json({ transactions });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ---- Withdrawals list ----
router.get('/withdrawals', async (req, res) => {
  try {
    if (!(await adminGate(req, res))) return;
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const limit = Math.min(parseInt(req.query.limit) || 100, 500);
    const snap = await db.collection('withdrawals').orderBy('createdAt', 'desc').limit(limit).get();
    const withdrawals = snap.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
    res.json({ withdrawals });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ---- Analytics ----
router.get('/analytics', async (req, res) => {
  try {
    if (!(await adminGate(req, res))) return;
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const result = await memGet('admin.analytics', 45_000, async () => {
      const now = new Date();
      const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
      const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);

      const [usersSnap, productsSnap, txSnap, sessionsSnap] = await Promise.all([
        db.collection('users').get(),
        db.collection('products').get(),
        db.collection('transactions').get(),
        db.collection('user_sessions').get(),
      ]);

      let totalUsers = 0, newUsersToday = 0, newUsersThisMonth = 0;
      const locationDistribution = {};
      const ageDistribution = {};
      for (const doc of usersSnap.docs) {
        totalUsers++;
        const d = doc.data();
        const createdAt = d.createdAt ? (d.createdAt.toDate ? d.createdAt.toDate() : new Date(d.createdAt)) : null;
        if (createdAt) {
          if (createdAt >= todayStart) newUsersToday++;
          if (createdAt >= monthStart) newUsersThisMonth++;
        }
        const loc = d.location;
        if (loc) locationDistribution[loc] = (locationDistribution[loc] || 0) + 1;
        const dob = d.dateOfBirth;
        if (dob) {
          try {
            const birth = new Date(dob);
            const age = now.getFullYear() - birth.getFullYear();
            const group = age < 18 ? 'Under 18' : age < 25 ? '18-24' : age < 35 ? '25-34' : age < 50 ? '35-49' : '50+';
            ageDistribution[group] = (ageDistribution[group] || 0) + 1;
          } catch (_) {}
        }
      }

      let totalProducts = 0, activeProducts = 0, inactiveProducts = 0;
      const productsByCategory = {};
      for (const doc of productsSnap.docs) {
        totalProducts++;
        const d = doc.data();
        if (d.isActive !== false) activeProducts++; else inactiveProducts++;
        const cat = d.category || 'Other';
        productsByCategory[cat] = (productsByCategory[cat] || 0) + 1;
      }

      // revenue aggregations
      let totalRevenue = 0, revenueToday = 0, revenueThisMonth = 0;
      const day0 = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 6);
      const revByDay = new Array(7).fill(0);
      const grwByDay = new Array(7).fill(0);
      const bucketFor = (t) => {
        const c = new Date(t.getFullYear(), t.getMonth(), t.getDate());
        return Math.round((c - day0) / 86400000);
      };
      for (const doc of txSnap.docs) {
        const d = doc.data();
        const status = d.status || '';
        const amount = d.totalAmount || 0;
        const createdAt = d.createdAt ? (d.createdAt.toDate ? d.createdAt.toDate() : new Date(d.createdAt)) : null;
        if (!PAYED_STATUSES.has(status)) continue;
        totalRevenue += amount;
        if (createdAt) {
          if (createdAt >= todayStart) revenueToday += amount;
          if (createdAt >= monthStart) revenueThisMonth += amount;
          const b = bucketFor(createdAt);
          if (b >= 0 && b < 7) revByDay[b] += amount;
        }
      }
      for (const doc of usersSnap.docs) {
        const d = doc.data();
        const createdAt = d.createdAt ? (d.createdAt.toDate ? d.createdAt.toDate() : new Date(d.createdAt)) : null;
        if (!createdAt) continue;
        const b = bucketFor(createdAt);
        if (b >= 0 && b < 7) grwByDay[b]++;
      }

      const revenueOverTime = [];
      const userGrowth = [];
      for (let i = 0; i < 7; i++) {
        const date = new Date(day0.getTime() + i * 86400000).toISOString();
        revenueOverTime.push({ date, count: Math.round(revByDay[i]) });
        userGrowth.push({ date, count: grwByDay[i] });
      }

      let perSecond = 0, perMinute = 0, perHour = 0, perDay = 0, perMonth = 0, perYear = 0;
      for (const doc of sessionsSnap.docs) {
        const ts = doc.data().lastActive;
        const lastActive = ts ? (ts.toDate ? ts.toDate() : new Date(ts)) : null;
        if (!lastActive) continue;
        const diffMs = now - lastActive;
        if (diffMs <= 1000) perSecond++;
        if (diffMs <= 60000) perMinute++;
        if (diffMs <= 3600000) perHour++;
        if (diffMs <= 86400000) perDay++;
        if (diffMs <= 2592000000) perMonth++;
        if (diffMs <= 31536000000) perYear++;
      }

      return {
        success: true,
        totalUsers, newUsersToday, newUsersThisMonth,
        totalProducts, activeProducts, inactiveProducts,
        productsByCategory,
        totalRevenue, revenueToday, revenueThisMonth,
        revenueOverTime, userGrowth,
        locationDistribution, ageDistribution,
        activeUserCounts: { perSecond, perMinute, perHour, perDay, perMonth, perYear, allTime: sessionsSnap.docs.length },
      };
    });

    res.json(result);
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ---- Daily time-series ----
router.get('/timeseries', async (req, res) => {
  try {
    if (!(await adminGate(req, res))) return;
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const days = Math.min(parseInt(req.query.days) || 30, 90);
    const result = await memGet('admin.ts.' + days, 45_000, async () => {
      const now = new Date();

      const series = [];
      for (let i = days - 1; i >= 0; i--) {
        const day = new Date(now.getFullYear(), now.getMonth(), now.getDate() - i);
        series.push({ date: day.toISOString().slice(0, 10), money: 0, commission: 0, users: 0 });
      }
      const index = new Map(series.map((s, i) => [s.date, i]));
      const start = new Date(now.getFullYear(), now.getMonth(), now.getDate() - (days - 1));

      const [txSnap, usersSnap] = await Promise.all([
        db.collection('transactions').get(),
        db.collection('users').get(),
      ]);

      for (const doc of txSnap.docs) {
        const d = doc.data();
        if (!PAYED_STATUSES.has(d.status || '')) continue;
        const created = d.createdAt ? (d.createdAt.toDate ? d.createdAt.toDate() : new Date(d.createdAt)) : null;
        if (!created || created < start) continue;
        const i = index.get(created.toISOString().slice(0, 10));
        if (i === undefined) continue;
        series[i].money += (d.totalAmount || 0);
        series[i].commission += (d.sokoLanguCommission || d.sokovibeCommission || d.platformFee || d.platformCommission || 0);
      }

      for (const doc of usersSnap.docs) {
        const d = doc.data();
        const created = d.createdAt ? (d.createdAt.toDate ? d.createdAt.toDate() : new Date(d.createdAt)) : null;
        if (!created || created < start) continue;
        const i = index.get(created.toISOString().slice(0, 10));
        if (i === undefined) continue;
        series[i].users++;
      }

      return { success: true, series };
    });

    res.json(result);
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ---- Online / presence ----
router.get('/online', async (req, res) => {
  try {
    if (!(await adminGate(req, res))) return;
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const result = await memGet('admin.online', 15_000, async () => {
      const [sessionsSnap, usersCountSnap] = await Promise.all([
        db.collection('user_sessions').get(),
        db.collection('users').count().get(),
      ]);

      const now = Date.now();
      let lastMinute = 0, last5Min = 0, last15Min = 0, lastHour = 0, lastDay = 0;
      const recent = [];
      for (const doc of sessionsSnap.docs) {
        const ts = doc.data().lastActive;
        const lastActive = ts ? (ts.toDate ? ts.toDate().getTime() : new Date(ts).getTime()) : 0;
        if (!lastActive) continue;
        const diff = now - lastActive;
        if (diff <= 60000) lastMinute++;
        if (diff <= 300000) last5Min++;
        if (diff <= 900000) last15Min++;
        if (diff <= 3600000) lastHour++;
        if (diff <= 86400000) lastDay++;
        if (diff <= 600000) recent.push({ uid: doc.id, lastActive });
      }
      recent.sort((a, b) => b.lastActive - a.lastActive);

      return {
        success: true,
        totalUsers: (usersCountSnap.data() || {}).count || 0,
        online: { lastMinute, last5Min, last15Min, lastHour, lastDay },
        recentlyActive: recent.slice(0, 30),
        asOf: now,
      };
    });

    res.json(result);
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ---- Finance summary ----
router.get('/finance-summary', async (req, res) => {
  try {
    if (!(await adminGate(req, res))) return;
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const result = await memGet('admin.finance', 30_000, async () => {
      // All Firestore reads run in parallel — previously serialized (6 waits)
      // — so one cold compute ≈ max(read), not the sum.
      const [adSnap, admobSnap, revSnap, txSnap, withdrawSnap, adminWithdrawSnap, clickRes] = await Promise.allSettled([
        db.collection('ad_views').count().get(),
        db.collection('admob_earnings').orderBy('month', 'desc').limit(1).get(),
        db.collection('revenue_transactions').get(),
        db.collection('transactions').get(),
        db.collection('withdrawals').get(),
        db.collection('admin_withdrawals').get(),
        memGet('clickpesa.balance', 120_000, () => clickpesaBalance()),
      ]);

      const estimatedAdRevenue = (adSnap.status === 'fulfilled' ? adSnap.value.data().count : 0) * AD_REVENUE_PER_VIEW;

      let actualAdRevenue = 0;
      const admob = admobSnap.status === 'fulfilled' ? admobSnap.value : null;
      if (admob && !admob.empty) actualAdRevenue = admob.docs[0].data().amount || 0;

      let totalCommissions = 0, totalBoostRevenue = 0;
      if (revSnap.status === 'fulfilled') {
        revSnap.value.docs.forEach((doc) => {
          const d = doc.data();
          if (d.type === 'boost') totalBoostRevenue += (d.sokoLanguCommission || 0);
          else totalCommissions += (d.sokoLanguCommission || 0);
        });
      }

      const totalAdminBalance = actualAdRevenue + totalCommissions + totalBoostRevenue;

      let totalProcessed = 0;
      if (txSnap.status === 'fulfilled') {
        txSnap.value.docs.forEach((doc) => {
          const d = doc.data();
          if (PAYED_STATUSES.has(d.status)) totalProcessed += (d.totalAmount || 0);
        });
      }

      let totalPaidOut = 0;
      if (withdrawSnap.status === 'fulfilled') {
        withdrawSnap.value.docs.forEach((doc) => {
          const d = doc.data();
          if (d.status === 'completed') totalPaidOut += (d.netAmount || d.amount || 0);
        });
      }

      let totalAdminPaidOut = 0, totalAdminWithdrawn = 0;
      if (adminWithdrawSnap.status === 'fulfilled') {
        adminWithdrawSnap.value.docs.forEach((doc) => {
          const d = doc.data();
          if (d.status === 'completed') {
            totalAdminPaidOut += (d.netAmount || d.amount || 0);
            totalAdminWithdrawn += (d.amount || 0);
          }
        });
      }

      const totalPayouts = totalPaidOut + totalAdminPaidOut;
      const availableBalance = totalCommissions + totalBoostRevenue - totalAdminPaidOut;
      const actualClickPesaBalance = clickRes.status === 'fulfilled' ? (clickRes.value || 0) : 0;

      return {
        success: true,
        estimatedAdRevenue,
        actualAdRevenue,
        totalCommissions,
        totalBoostRevenue,
        totalAdminBalance,
        totalProcessed,
        totalUserPaidOut: totalPaidOut,
        totalAdminPaidOut,
        totalPayouts,
        totalPaidOut: totalPayouts,
        availableBalance,
        totalAdminWithdrawn,
        actualClickPesaBalance,
        paymentProcessor: 'ClickPesa',
        platformCommissionPercent: PLATFORM_COMMISSION_PERCENT,
        adRevenuePerView: AD_REVENUE_PER_VIEW,
      };
    });

    res.json(result);
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ---- ClickPesa visibility ----
router.get('/clickpesa/transactions', async (req, res) => {
  try {
    if (!(await adminGate(req, res))) return;
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const { type = 'all', status = '', channel = '', currency = '', startDate = '', endDate = '', limit = '100' } = req.query;
    const maxLimit = Math.min(Math.max(parseInt(limit, 10) || 100, 1), 500);
    const baseFilters = { limit: String(maxLimit), sortBy: 'createdAt', orderBy: 'DESC' };
    if (status) baseFilters.status = String(status).toUpperCase();
    if (channel) baseFilters.channel = String(channel);
    if (currency) baseFilters.collectedCurrency = String(currency).toUpperCase();
    if (startDate) baseFilters.startDate = String(startDate);
    if (endDate) baseFilters.endDate = String(endDate);

    const [balancesRes, paymentsRes, payoutsRes] = await Promise.allSettled([
      clickpesaRawBalances(),
      type === 'payouts' ? Promise.resolve({ data: [], totalCount: 0 }) : clickpesaQueryPayments(baseFilters),
      type === 'payments' ? Promise.resolve({ data: [], totalCount: 0 }) : clickpesaQueryPayouts({ ...baseFilters, collectedCurrency: undefined, channel: channel || undefined }),
    ]);

    const balances = balancesRes.status === 'fulfilled' ? balancesRes.value : [];
    const payments = paymentsRes.status === 'fulfilled' ? paymentsRes.value : { data: [], totalCount: 0 };
    const payouts = payoutsRes.status === 'fulfilled' ? payoutsRes.value : { data: [], totalCount: 0 };

    const paymentsData = Array.isArray(payments.data) ? payments.data : [];
    const payoutsData = Array.isArray(payouts.data) ? payouts.data : [];

    const summarize = (rows, moneyField) => {
      const totals = {};
      const channelTotals = {};
      let sum = 0;
      for (const row of rows) {
        const amt = Number(row[moneyField] || 0) || 0;
        const st = (row.status || 'UNKNOWN').toUpperCase();
        totals[st] = (totals[st] || 0) + amt;
        const ch = row.channel || 'OTHER';
        channelTotals[ch] = (channelTotals[ch] || 0) + amt;
        sum += amt;
      }
      return { total: sum, byStatus: totals, byChannel: channelTotals };
    };

    res.json({
      success: true,
      balances,
      payments: {
        data: paymentsData,
        totalCount: payments.totalCount || paymentsData.length,
        summary: summarize(paymentsData, 'collectedAmount'),
      },
      payouts: {
        data: payoutsData,
        totalCount: payouts.totalCount || payoutsData.length,
        summary: summarize(payoutsData, 'amount'),
      },
      asOf: new Date().toISOString(),
    });
  } catch (e) {
    console.error('ClickPesa admin transactions error:', e?.message || e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ---- Users list ----
router.get('/users', async (req, res) => {
  try {
    if (!(await adminGate(req, res))) return;
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const result = await memGet('admin.users', 60_000, async () => {
      const snap = await db.collection('users').orderBy('createdAt', 'desc').get();
      const users = snap.docs.map((doc) => {
        const u = { uid: doc.id, ...doc.data() };
        if (typeof u.sellerBalance !== 'undefined') u.sellerBalance = Math.max(0, u.sellerBalance || 0);
        if (typeof u.pendingEscrow !== 'undefined') u.pendingEscrow = Math.max(0, u.pendingEscrow || 0);
        if (typeof u.coins !== 'undefined') u.coins = Math.max(0, u.coins || 0);
        return u;
      });
      return { users };
    });

    res.json(result);
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ---- Update user ----
router.put('/users/:uid', async (req, res) => {
  try {
    if (!(await adminGate(req, res))) return;
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const { uid } = req.params;
    const updates = {};
    const allowed = ['isAdmin', 'isSuspended', 'displayName', 'phone'];
    for (const field of allowed) {
      if (req.body[field] !== undefined) updates[field] = req.body[field];
    }
    if (Object.keys(updates).length === 0) {
      return res.status(400).json({ error: 'No valid fields to update' });
    }
    await db.collection('users').doc(uid).update(updates);
    clearAdminCache();
    res.json({ updated: true, uid, updates });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ---- Products list ----
router.get('/products', async (req, res) => {
  try {
    if (!(await adminGate(req, res))) return;
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const result = await memGet('admin.products', 60_000, async () => {
      const snap = await db.collection('products').orderBy('createdAt', 'desc').get();
      const products = snap.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
      return { products };
    });

    res.json(result);
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ---- Update product ----
router.put('/products/:id', async (req, res) => {
  try {
    if (!(await adminGate(req, res))) return;
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const { id } = req.params;
    const updates = {};
    const allowed = ['isActive', 'isFeatured', 'featuredUntil'];
    for (const field of allowed) {
      if (req.body[field] !== undefined) updates[field] = req.body[field];
    }
    if (Object.keys(updates).length === 0) {
      return res.status(400).json({ error: 'No valid fields to update' });
    }
    await db.collection('products').doc(id).update(updates);
    clearAdminCache();
    res.json({ updated: true, id, updates });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ---- Orders list ----
router.get('/orders', async (req, res) => {
  try {
    if (!(await adminGate(req, res))) return;
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const result = await memGet('admin.orders', 60_000, async () => {
      const snap = await db.collection('orders').orderBy('createdAt', 'desc').get();
      const orders = snap.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
      return { orders };
    });

    res.json(result);
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ---- Update order status ----
router.put('/orders/:id', async (req, res) => {
  try {
    if (!(await adminGate(req, res))) return;
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const { id } = req.params;
    const { status } = req.body;
    const validStatuses = ['pending', 'confirmed', 'processing', 'shipped', 'delivered', 'cancelled'];
    if (!status || !validStatuses.includes(status)) {
      return res.status(400).json({ error: 'Invalid status' });
    }
    await db.collection('orders').doc(id).update({ status });
    await auditLog({ type: 'order_status_change', reason: `Order ${id} status → ${status}` });
    clearAdminCache();
    res.json({ updated: true, id, status });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ---- KYC pending ----
router.get('/kyc/pending', async (req, res) => {
  try {
    if (!(await adminGate(req, res))) return;
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const snap = await db.collection('users').where('kyc.status', '==', 'pending').limit(50).get();
    const pending = snap.docs.map((doc) => ({
      uid: doc.id,
      displayName: doc.data().displayName || '',
      email: doc.data().email || '',
      phone: doc.data().phone || '',
      kyc: doc.data().kyc || {},
    }));
    res.json({ pending });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ---- KYC review ----
router.post('/kyc/review', async (req, res) => {
  try {
    if (!(await adminGate(req, res))) return;
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const { userId, approve, notes } = req.body;
    if (!userId) return res.status(400).json({ error: 'Missing userId' });

    const status = approve ? 'approved' : 'rejected';

    await db.collection('users').doc(userId).update({
      'kyc.status': status,
      'kyc.reviewedAt': admin.firestore.FieldValue.serverTimestamp(),
      'kyc.reviewNotes': notes || '',
      'kyc.approved': approve === true,
    });

    await db.collection('notifications').add({
      userId,
      title: approve ? 'KYC Imekubaliwa!' : 'KYC Imekataliwa',
      body: approve
        ? 'Umekubaliwa kuuza bidhaa. Sasa unaweza kuongeza bidhaa mpya.'
        : `KYC yako imekataliwa. Sababu: ${notes || 'Tafadhali wasiliana na msaada'}. Wasilisha tena baada ya kurekebisha.`,
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    try {
      await sendOneSignalNotification(
        userId,
        approve ? 'KYC Imekubaliwa!' : 'KYC Imekataliwa',
        approve
          ? 'Umekubaliwa kuuza bidhaa. Sasa unaweza kuongeza bidhaa mpya.'
          : `KYC yako imekataliwa. Sababu: ${notes || 'Tafadhali wasiliana na msaada'}. Wasilisha tena baada ya kurekebisha.`,
        { type: 'kyc', status: approve ? 'approved' : 'rejected' }
      );
    } catch (_) {}

    if (approve && userId) {
      await updateSellerKycOnProducts(userId, true);
    }

    await auditLog({
      userId,
      type: `kyc_${status}`,
      amount: 0,
      reason: `KYC ${status} by admin. Notes: ${notes || ''}`,
    });

    clearAdminCache();

    res.json({ success: true, message: `KYC ${status}` });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ---- Audit log ----
router.get('/audit-log', async (req, res) => {
  try {
    if (!(await adminGate(req, res))) return;
    if (!db) return res.status(503).json({ error: 'Database not configured' });

    const limit = Math.min(parseInt(req.query.limit) || 100, 500);
    const snap = await db.collection('audit_log').orderBy('timestamp', 'desc').limit(limit).get();
    const logs = snap.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
    res.json({ logs });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ---- Reports & fraud alerts (panel sections that live outside /api/admin) ----
const publicRouter = express.Router();

publicRouter.get('/reports', async (req, res) => {
  try {
    if (!(await adminGate(req, res))) return;
    if (!db) return res.status(503).json({ error: 'Database not configured' });
    const limit = Math.min(parseInt(req.query.limit) || 200, 500);
    const snap = await db.collection('reports').orderBy('createdAt', 'desc').limit(limit).get();
    const reports = snap.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
    res.json({ reports });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

publicRouter.get('/fraud/alerts', async (req, res) => {
  try {
    if (!(await adminGate(req, res))) return;
    if (!db) return res.status(503).json({ error: 'Database not configured' });
    const limit = Math.min(parseInt(req.query.limit) || 200, 500);
    const snap = await db.collection('fraud_alerts').orderBy('createdAt', 'desc').limit(1000).get();
    let alerts = snap.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
    if (req.query.resolved === 'false') alerts = alerts.filter((a) => a.resolved === false);
    alerts = alerts.slice(0, limit);
    res.json({ alerts });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
module.exports.publicRouter = publicRouter;