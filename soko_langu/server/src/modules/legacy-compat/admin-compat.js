// Compat admin router: verbatim port of the proven old-server /api/admin
// handlers (stats, analytics, users, products, orders, transactions,
// withdrawals, KYC, finance, audit). Firestore is the same project, so the
// browser admin panel keeps working with zero client changes. Admin gating
// mirrors the old semantics: x-admin-secret OR Firebase admin (isAdmin flag).
const express = require('express');
const { requireAdmin } = require('./auth-helpers');
const { sendOneSignalNotification } = require('./notify');
const OrderService = require('../orders/order-service');

const commerceStore = require('../../services/commerce-store');

const {
  clickpesaBalance,
  clickpesaRawBalances,
  clickpesaQueryPayments,
  clickpesaQueryPayouts,
} = require('../../../clickpesa');

// Platform commission (Terms 8.2: 3.5% buyer-pays-top). Config-driven so env can
// still steer it without a deploy.
const config = require('../../config');
const PLATFORM_COMMISSION_PERCENT = config.business.platformCommissionPercent;
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
  if (!sellerId) return;
  try {
    const productsList = await commerceStore.listDocuments('products', { where: { sellerId } });
    if (productsList.length === 0) return;
    await commerceStore.batchUpdate(productsList.map(doc => ({
      collection: 'products',
      docId: doc.id,
      data: { sellerKycApproved: kycApproved }
    })));
  } catch (e) {
    console.error(`Failed to update sellerKycApproved for ${sellerId}:`, e);
  }
}

async function auditLog(entry) {
  await commerceStore.writeAuditLog({
    actorId: entry.userId || null,
    actorType: 'admin',
    action: entry.type || 'admin_action',
    entityType: 'system',
    entityId: null,
    oldState: null,
    newState: null,
    requestId: null,
    ipAddress: null,
    userAgent: null,
  });
}

const router = express.Router();

async function adminGate(req, res) {
  const auth = await requireAdmin(req, res);
  return auth.ok ? auth : null;
}

// ---- Dashboard KPIs ----
router.get('/stats', async (req, res) => {
  try {
    if (!(await adminGate(req, res))) return;

    const result = await memGet('admin.stats', 30_000, async () => {
      const [usersSnap, ordersSnap, withdrawalsSnap, adViewsSnap] = await Promise.all([
        commerceStore.countDocuments(commerceStore.COLLECTIONS.users),
        OrderService.countOrders(),
        commerceStore.countDocuments(commerceStore.COLLECTIONS.withdrawals),
        commerceStore.countDocuments('ad_views'),
      ]);

      const totalSellerBalance = await commerceStore.sumField(commerceStore.COLLECTIONS.users, 'sellerBalance');

      return {
        totalUsers: usersSnap,
        totalOrders: ordersSnap,
        totalWithdrawals: withdrawalsSnap,
        totalAdViews: adViewsSnap,
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

    const limit = Math.min(parseInt(req.query.limit) || 100, 500);
    const transactions = await commerceStore.listDocuments(commerceStore.COLLECTIONS.transactions, {
      orderBy: 'createdAt',
      limit: limit,
    });
    res.json({ transactions });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ---- Withdrawals list ----
router.get('/withdrawals', async (req, res) => {
  try {
    if (!(await adminGate(req, res))) return;

    const limit = Math.min(parseInt(req.query.limit) || 100, 500);
    const withdrawals = await commerceStore.listDocuments(commerceStore.COLLECTIONS.withdrawals, {
      orderBy: 'createdAt',
      limit: limit,
    });
    res.json({ withdrawals });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ---- Analytics ----
router.get('/analytics', async (req, res) => {
  try {
    if (!(await adminGate(req, res))) return;

    const result = await memGet('admin.analytics', 45_000, async () => {
      const now = new Date();
      const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
      const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);

      const [usersSnap, productsSnap, txSnap, sessionsSnap] = await Promise.all([
        commerceStore.listDocuments('users'),
        commerceStore.listDocuments('products'),
        commerceStore.listDocuments('transactions'),
        commerceStore.listDocuments('user_sessions'),
      ]);

      let totalUsers = 0, newUsersToday = 0, newUsersThisMonth = 0;
      const locationDistribution = {};
      const ageDistribution = {};
      for (const doc of usersSnap) {
        totalUsers++;
        const d = doc;
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
      for (const doc of productsSnap) {
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
      for (const doc of txSnap) {
        const d = doc;
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
      for (const doc of usersSnap) {
        const d = doc;
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
      for (const doc of sessionsSnap) {
        const ts = doc.lastActive;
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
        activeUserCounts: { perSecond, perMinute, perHour, perDay, perMonth, perYear, allTime: sessionsSnap.length },
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
        commerceStore.listDocuments('transactions'),
        commerceStore.listDocuments('users'),
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

      for (const doc of usersSnap) {
        const d = doc;
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

    const result = await memGet('admin.online', 15_000, async () => {
      const [sessionsSnap, usersCountSnap] = await Promise.all([
        commerceStore.listDocuments('user_sessions'),
        commerceStore.countDocuments('users'),
      ]);

      const now = Date.now();
      let lastMinute = 0, last5Min = 0, last15Min = 0, lastHour = 0, lastDay = 0;
      const recent = [];
      for (const doc of sessionsSnap) {
        const ts = doc.lastActive;
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
        totalUsers: usersCountSnap || 0,
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

    const result = await memGet('admin.finance', 30_000, async () => {
      // All Firestore reads run in parallel — previously serialized (6 waits)
      // — so one cold compute ≈ max(read), not the sum.
      const [adSnap, admobSnap, revSnap, txSnap, withdrawSnap, adminWithdrawSnap, clickRes] = await Promise.allSettled([
        commerceStore.countDocuments('ad_views'),
        commerceStore.listDocuments('admob_earnings', { orderBy: 'month', direction: 'desc', limit: 1 }),
        commerceStore.listDocuments('revenue_transactions'),
        commerceStore.listDocuments('transactions'),
        commerceStore.listDocuments('withdrawals'),
        commerceStore.listDocuments('admin_withdrawals'),
        memGet('clickpesa.balance', 120_000, () => clickpesaBalance()),
      ]);

      const estimatedAdRevenue = (adSnap.status === 'fulfilled' ? adSnap.value : 0) * AD_REVENUE_PER_VIEW;

      let actualAdRevenue = 0;
      const admob = admobSnap.status === 'fulfilled' ? admobSnap.value : null;
      if (admob && admob.length > 0) actualAdRevenue = admob[0].amount || 0;

      // Platform revenue is split into distinct buckets so the admin panel can
      // tell apart commissions, boost placements, KYC verification fees, and
      // everything else (e.g. profanity seizures). `sale` rows carry no
      // platform revenue (seller earnings) and are deliberately skipped.
      let totalCommissions = 0, totalBoostRevenue = 0;
      let totalKycRevenue = 0, totalOtherRevenue = 0;
      if (revSnap.status === 'fulfilled') {
        revSnap.value.forEach((doc) => {
          const d = doc || {};
          const amt = Number(d.sokoLanguCommission || d.amount || 0) || 0;
          const type = String(d.type || '').toLowerCase();
          if (type === 'boost') totalBoostRevenue += amt;
          else if (type === 'kyc_fee') totalKycRevenue += amt;
          else if (type === 'sale') { /* seller earnings, not platform revenue */ }
          else if (type === 'profanity_seizure') totalOtherRevenue += amt;
          else totalCommissions += amt; // commission + any uncategorised platform revenue
        });
      }

      const totalPlatformRevenue = totalCommissions + totalBoostRevenue + totalKycRevenue + totalOtherRevenue;
      const totalAdminBalance = actualAdRevenue + totalPlatformRevenue;

      let totalProcessed = 0;
      if (txSnap.status === 'fulfilled') {
        txSnap.value.forEach((doc) => {
          const d = doc;
          if (PAYED_STATUSES.has(d.status)) totalProcessed += (d.totalAmount || 0);
        });
      }

      let totalPaidOut = 0;
      if (withdrawSnap.status === 'fulfilled') {
        withdrawSnap.value.forEach((doc) => {
          const d = doc;
          if (d.status === 'completed') totalPaidOut += (d.netAmount || d.amount || 0);
        });
      }

      let totalAdminPaidOut = 0, totalAdminWithdrawn = 0;
      if (adminWithdrawSnap.status === 'fulfilled') {
        adminWithdrawSnap.value.forEach((doc) => {
          const d = doc;
          if (d.status === 'completed') {
            totalAdminPaidOut += (d.netAmount || d.amount || 0);
            totalAdminWithdrawn += (d.amount || 0);
          }
        });
      }

      const totalPayouts = totalPaidOut + totalAdminPaidOut;
      // Only ClickPesa-collected platform revenue is withdrawable through
      // ClickPesa; AdMob revenue is settled by Google separately. Keep this in
      // sync with payouts.js /admin/withdraw.
      const availableBalance = totalPlatformRevenue - totalAdminPaidOut;
      const actualClickPesaBalance = clickRes.status === 'fulfilled' ? (clickRes.value || 0) : 0;

      return {
        success: true,
        estimatedAdRevenue,
        actualAdRevenue,
        totalCommissions,
        totalBoostRevenue,
        totalKycRevenue,
        totalOtherRevenue,
        totalPlatformRevenue,
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

// ---- Boost analytics (admin) ----
// Lists products that are currently boosted and the full boost purchase
// history (from revenue_transactions type='boost'). Both read straight from
// Firestore — the live data the app actually uses.
router.get('/analytics/boosts', async (req, res) => {
  try {
    if (!(await adminGate(req, res))) return;
    

    const [activeSnap, histSnap] = await Promise.allSettled([
      commerceStore.listDocuments('products', { where: { isBoosted: true }, limit: 200 }),
      commerceStore.listDocuments(commerceStore.COLLECTIONS.revenueTransactions, {
        orderBy: 'timestamp',
        limit: 300,
      }),
    ]);

    const active = [];
    if (activeSnap.status === 'fulfilled') {
      const now = Date.now();
      for (const doc of activeSnap.value) {
        const d = doc;
        const until = d.boostedUntil && d.boostedUntil.toDate ? d.boostedUntil.toDate() : (d.boostedUntil instanceof Date ? d.boostedUntil : null);
        if (until && until.getTime() < now) continue; // stale flag → not really active
        active.push({
          id: doc.id,
          title: d.title || d.name || '—',
          image: d.imageUrl && Array.isArray(d.imageUrl) ? d.imageUrl[0] : (d.mainImage || d.image || ''),
          price: d.price || 0,
          tier: d.boostTier || '—',
          boostedUntil: until ? until.toISOString() : d.boostedUntil,
          sellerId: d.sellerId || '',
          sellerName: d.sellerName || '',
        });
      }
      // One pass to fill seller display names (batch get)
      const sellerIds = [...new Set(active.map((a) => a.sellerId).filter(Boolean))];
      const nameMap = {};
      await Promise.all(sellerIds.map(async (sid) => {
        try {
          const u = await commerceStore.getDocument('users', sid);
          if (u) nameMap[sid] = u.displayName || u.email || '';
        } catch (_) {}
      }));
      active.forEach((a) => { if (!a.sellerName) a.sellerName = nameMap[a.sellerId] || ''; });
    }

    const history = [];
    if (histSnap.status === 'fulfilled') {
      const sellerIds = [...new Set(histSnap.value.map((doc) => doc.userId).filter(Boolean))];
      const nameMap = {};
      await Promise.all(sellerIds.map(async (sid) => {
        try {
          const u = await commerceStore.getDocument('users', sid);
          if (u) nameMap[sid] = u.displayName || u.email || '';
        } catch (_) {}
      }));
      histSnap.value.forEach((doc) => {
        const d = doc;
        // the query has no type filter (composite index risk), so keep only boosts
        if (d.type !== 'boost') return;
        const ts = d.timestamp && d.timestamp.toDate ? d.timestamp.toDate() : null;
        history.push({
          id: doc.id,
          sellerId: d.userId || '',
          sellerName: nameMap[d.userId] || '',
          tier: d.boostTier || (d.description || '').split(' ')[0] || '—',
          amount: d.amount || 0,
          commission: d.sokoLanguCommission || 0,
          description: d.description || '',
          timestamp: ts ? ts.toISOString() : null,
        });
      });
    }

    res.json({ activeCount: active.length, active, history });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ---- Flash sale analytics (admin) ----
// Every flash_sales doc (active, scheduled, ended) with seller + duration +
// performance so the admin can see who created which promotion and when it
// runs. Firebase Timestamps are down-converted to ISO strings for the panel.
router.get('/analytics/flash-sales', async (req, res) => {
  try {
    if (!(await adminGate(req, res))) return;
    

    const flashSalesList = await commerceStore.listDocuments('flash_sales', { orderBy: 'createdAt', direction: 'desc', limit: 300 });
    const now = Date.now();
    const flashSales = flashSalesList.map((doc) => {
      const d = doc;
      const toISO = (v) => (v && v.toDate ? v.toDate() : v instanceof Date ? v : null) ? ((v.toDate ? v.toDate() : v).toISOString()) : null;
      const start = toISO(d.startTime);
      const end = toISO(d.endTime);
      let status = 'ended';
      if (d.isActive === false) status = 'disabled';
      else if (end && new Date(end).getTime() > now && start && new Date(start).getTime() <= now) status = 'active';
      else if (start && new Date(start).getTime() > now) status = 'scheduled';
      return {
        id: doc.id,
        productId: d.productId || '',
        productImage: d.productImage || '',
        productName: d.productName || '',
        sellerId: d.sellerId || '',
        sellerName: d.sellerName || d.sellerPhone || '',
        location: d.location || '',
        originalPrice: d.originalPrice || 0,
        salePrice: d.salePrice || 0,
        discountPercent: d.discountPercent || 0,
        stock: d.stock || 0,
        soldCount: d.soldCount || 0,
        startTime: start,
        endTime: end,
        isActive: d.isActive !== false,
        status,
      };
    });

    const counts = { active: 0, scheduled: 0, ended: 0, disabled: 0 };
    flashSales.forEach((f) => { counts[f.status] = (counts[f.status] || 0) + 1; });

    res.json({ counts, flashSales });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ---- Platform revenue ledger ----
// revenue_transactions is the single source of platform earnings (commissions
// on orders + boost fees + refunds). Paged desc so the panel can browse.
router.get('/revenue-ledger', async (req, res) => {
  try {
    if (!(await adminGate(req, res))) return;

    const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 50, 1), 200);
    const offset = Math.max(parseInt(req.query.offset, 10) || 0, 0);
    const docs = await commerceStore.listDocuments(commerceStore.COLLECTIONS.revenueTransactions, {
      orderBy: 'timestamp',
      limit: limit + offset,
      offset: 0, // listDocuments handles offset internally if passed, but here we need to slice manually because we might be using a custom offset logic. Actually, commerceStore.listDocuments already has offset.
    });
    const slicedDocs = docs.slice(offset, offset + limit);

    const sellerIds = [...new Set(slicedDocs.map((d) => d.userId).filter(Boolean))];
    const nameMap = {};
    await Promise.all(sellerIds.map(async (sid) => {
      try {
        const u = await commerceStore.getDocument('users', sid);
        if (u) nameMap[sid] = u.displayName || u.email || '';
      } catch (_) {}
    }));

    const entries = slicedDocs.map((doc) => {
      const d = doc;
      const ts = d.timestamp && d.timestamp.toDate ? d.timestamp.toDate() : null;
      return {
        id: doc.id,
        userId: d.userId || '',
        userName: nameMap[d.userId] || '',
        type: d.type || 'other',
        amount: d.amount || 0,
        commission: d.sokoLanguCommission || 0,
        orderId: d.orderId || '',
        description: d.description || '',
        timestamp: ts ? ts.toISOString() : null,
      };
    });

    res.json({ entries, total: docs.length, limit, offset });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ---- Admin platform withdrawals (money taken OUT of platform revenue) ----
router.get('/revenue-withdrawals', async (req, res) => {
  try {
    if (!(await adminGate(req, res))) return;

    const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 50, 1), 200);
    const withdrawals = await commerceStore.listDocuments(commerceStore.COLLECTIONS.adminWithdrawals, {
      orderBy: 'createdAt',
      limit: limit,
    });
    const results = withdrawals.map((doc) => {
      const d = doc;
      const ts = d.createdAt && d.createdAt.toDate ? d.createdAt.toDate() : null;
      return {
        id: doc.id,
        userId: d.userId || '',
        amount: d.amount || 0,
        fee: d.fee || 0,
        netAmount: d.netAmount || d.amount || 0,
        phone: d.phone || '',
        payoutId: d.payoutId || '',
        status: d.status || 'pending',
        createdAt: ts ? ts.toISOString() : null,
      };
    });
    res.json({ withdrawals: results, total: withdrawals.length });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ---- ClickPesa visibility ----
router.get('/clickpesa/transactions', async (req, res) => {
  try {
    if (!(await adminGate(req, res))) return;
    

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
    

    const result = await memGet('admin.users', 60_000, async () => {
      const usersList = await commerceStore.listDocuments('users', { orderBy: 'createdAt', direction: 'desc' });
      const users = usersList.map((u) => {
        const user = { uid: u.id, ...u };
        delete user.id;
        if (typeof user.sellerBalance !== 'undefined') user.sellerBalance = Math.max(0, user.sellerBalance || 0);
        if (typeof user.pendingEscrow !== 'undefined') user.pendingEscrow = Math.max(0, user.pendingEscrow || 0);
        if (typeof user.coins !== 'undefined') user.coins = Math.max(0, user.coins || 0);
        return user;
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
    

    const { uid } = req.params;
    const updates = {};
    const allowed = ['isAdmin', 'isSuspended', 'displayName', 'phone'];
    for (const field of allowed) {
      if (req.body[field] !== undefined) updates[field] = req.body[field];
    }
    if (Object.keys(updates).length === 0) {
      return res.status(400).json({ error: 'No valid fields to update' });
    }
    await commerceStore.updateDocument('users', uid, updates);
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
    

    const result = await memGet('admin.products', 60_000, async () => {
      const products = await commerceStore.listDocuments('products', { orderBy: 'createdAt', direction: 'desc' });
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
    

    const { id } = req.params;
    const updates = {};
    const allowed = ['isActive', 'isFeatured', 'featuredUntil'];
    for (const field of allowed) {
      if (req.body[field] !== undefined) updates[field] = req.body[field];
    }
    if (Object.keys(updates).length === 0) {
      return res.status(400).json({ error: 'No valid fields to update' });
    }
    await commerceStore.updateDocument('products', id, updates);
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
    

    const result = await memGet('admin.orders', 60_000, async () => {
      const orders = await OrderService.listOrders();
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
    const auth = await adminGate(req, res);
    if (!auth) return;
    

    const { id } = req.params;
    const { status } = req.body;

    await OrderService.adminUpdateOrderStatus(id, status, auth.uid);
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
    

    const pendingList = await commerceStore.listDocuments('users', { where: { 'kyc.status': 'pending' }, limit: 50 });
    const pending = pendingList.map((u) => ({
      uid: u.id,
      displayName: u.displayName || '',
      email: u.email || '',
      phone: u.phone || '',
      kyc: u.kyc || {},
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
    

    const { userId, approve, notes } = req.body;
    if (!userId) return res.status(400).json({ error: 'Missing userId' });

    const status = approve ? 'approved' : 'rejected';

    await commerceStore.updateDocument('users', userId, {
      'kyc.status': status,
      'kyc.reviewedAt': commerceStore.serverTimestamp(),
      'kyc.reviewNotes': notes || '',
      'kyc.approved': approve === true,
    });

    await commerceStore.addDocument('notifications', {
      userId,
      title: approve ? 'KYC Imekubaliwa!' : 'KYC Imekataliwa',
      body: approve
        ? 'Umekubaliwa kuuza bidhaa. Sasa unaweza kuongeza bidhaa mpya.'
        : `KYC yako imekataliwa. Sababu: ${notes || 'Tafadhali wasiliana na msaada'}. Wasilisha tena baada ya kurekebisha.`,
      isRead: false,
      createdAt: commerceStore.serverTimestamp(),
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

// ---- KYC all statuses (admin) ----
// ---- KYC all, filterable by state + searchable + paginated ----
//
// The panel needs to review every state and find a specific applicant.
//
// Firestore cannot search across displayName/email and kyc.status in one query,
// and ordering by kyc.submittedAt alongside the kyc.status 'in' filter needs a
// composite index that does not exist — that combination fails the request
// outright with FAILED_PRECONDITION. So: keep the single-field filter (which
// uses the built-in index), page it with offset, sort in JS, then slice. The
// queue is small and human-paced, so a bounded read beats an index migration
// that has to be built before the panel works again.
const KYC_STATUSES = ['pending', 'approved', 'rejected', 'revoked'];
const KYC_PAGE_SCAN = 200;
const KYC_MAX_SCAN = 2000;

function kycTimeMs(v) {
  if (!v) return 0;
  if (typeof v === 'object') {
    if (typeof v.toMillis === 'function') return v.toMillis();
    if (typeof v.toDate === 'function') return v.toDate().getTime();
    if (typeof v._seconds === 'number') return v._seconds * 1000;
  }
  const t = new Date(v).getTime();
  return Number.isFinite(t) ? t : 0;
}

function kycMatches(d, needle) {
  if (!needle) return true;
  const hay = [d.uid, d.displayName, d.email, d.phone, d.kyc && d.kyc.fullName, d.kyc && d.kyc.idNumber]
    .filter(Boolean)
    .join(' ')
    .toLowerCase();
  return hay.indexOf(needle) !== -1;
}

async function collectKyc({ status, q, limit, skip }) {
  const needle = String(q || '').trim().toLowerCase();
  const want = Math.max(1, Number(limit) || 50);
  const offset = Math.max(0, Number(skip) || 0);
  const matched = [];

  let scanned = 0;
  while (scanned < KYC_MAX_SCAN) {
    const take = Math.min(KYC_PAGE_SCAN, KYC_MAX_SCAN - scanned);
    const docs = await commerceStore.listDocuments('users', {
      where: [{ field: 'kyc.status', op: 'in', value: KYC_STATUSES }],
      offset: scanned,
      limit: take,
    });
    scanned += docs.length;
    for (const doc of docs) {
      const d = doc;
      if (status && status !== 'all' && d.kyc.status !== status) continue;
      const row = {
        uid: doc.id,
        displayName: d.displayName || '',
        email: d.email || '',
        phone: d.phone || '',
        kyc: d.kyc || {},
        _t: kycTimeMs(d.kyc && d.kyc.submittedAt),
      };
      if (!kycMatches(row, needle)) continue;
      matched.push(row);
    }
    if (docs.length < take) break;
  }

  matched.sort((a, b) => b._t - a._t);
  const rows = matched.slice(offset, offset + want).map((r) => ({
    uid: r.uid,
    displayName: r.displayName,
    email: r.email,
    phone: r.phone,
    kyc: r.kyc,
  }));
  return { rows, total: matched.length, truncated: scanned >= KYC_MAX_SCAN };
}

router.get('/kyc/all', async (req, res) => {
  try {
    if (!(await adminGate(req, res))) return;
    

    const { rows, total, truncated } = await collectKyc({
      status: req.query.status,
      q: req.query.q,
      limit: req.query.limit,
      skip: req.query.skip,
    });
    res.json({ all: rows, total, states: KYC_STATUSES, truncated: Boolean(truncated) });
  } catch (e) {
    // Log the real cause: a bare 500 here hid a Firestore index requirement
    // (FAILED_PRECONDITION on kyc.status + kyc.submittedAt) that only surfaced
    // as "Internal server error" in the panel.
    console.error('[KYC][LIST]', e && e.code ? e.code : '', e && e.message ? e.message : e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ---- KYC revoke (admin) ----
router.post('/kyc/revoke', async (req, res) => {
  try {
    if (!(await adminGate(req, res))) return;
    

    const { userId, reason } = req.body;
    if (!userId) return res.status(400).json({ error: 'Missing userId' });

    await commerceStore.updateDocument('users', userId, {
      'kyc.status': 'revoked',
      'kyc.approved': false,
      'kyc.revokedAt': commerceStore.serverTimestamp(),
      'kyc.reviewNotes': reason || 'KYC imefutwa na admin.',
    });

    await updateSellerKycOnProducts(userId, false);

    await commerceStore.addDocument('audit_log', {
      userId,
      type: 'kyc_revoked',
      amount: 0,
      reason: `KYC revoked by admin. Reason: ${reason || ''}`,
      timestamp: commerceStore.serverTimestamp(),
    });

    await commerceStore.addDocument('notifications', {
      userId,
      title: 'KYC Imefutwa',
      body: `KYC yako imefutwa na admin. Sababu: ${reason || 'Wasiliana na msaada'}. Tuma tena KYC yako.`,
      isRead: false,
      createdAt: commerceStore.serverTimestamp(),
    });

    clearAdminCache();
    res.json({ success: true, message: 'KYC revoked' });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ---- KYC delete (admin) ----
// Resets the user's KYC to 'none' so they can re-submit. Mirrors the v1
// admin router's DELETE semantics; the Flutter admin panel calls this as
// POST /api/admin/kyc/delete (admin_kyc_screen.dart).
router.post('/kyc/delete', async (req, res) => {
  try {
    if (!(await adminGate(req, res))) return;
    

    const { userId } = req.body;
    if (!userId) return res.status(400).json({ error: 'Missing userId' });

    await commerceStore.updateDocument('users', userId, {
      kyc: {
        status: 'none',
        approved: false,
        reviewNotes: '',
        reviewedAt: null,
        revokedAt: null,
      },
    });

    await updateSellerKycOnProducts(userId, false);

    await auditLog({
      userId,
      type: 'kyc_deleted',
      amount: 0,
      reason: 'KYC deleted by admin.',
    });

    await commerceStore.addDocument('notifications', {
      userId,
      title: 'KYC Imefutwa',
      body: 'KYC yako imefutwa na admin. Tuma tena KYC yako inapohitajika.',
      isRead: false,
      createdAt: commerceStore.serverTimestamp(),
    });

    clearAdminCache();
    res.json({ success: true, message: 'KYC deleted' });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ---- Audit log ----
router.get('/audit-log', async (req, res) => {
  try {
    if (!(await adminGate(req, res))) return;
    

    const limit = Math.min(parseInt(req.query.limit) || 100, 500);
    const logs = await commerceStore.listDocuments('audit_log', { orderBy: 'timestamp', direction: 'desc', limit });
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
    
    const limit = Math.min(parseInt(req.query.limit) || 200, 500);
    const reports = await commerceStore.listDocuments('reports', { orderBy: 'createdAt', direction: 'desc', limit });
    res.json({ reports });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

publicRouter.get('/fraud/alerts', async (req, res) => {
  try {
    if (!(await adminGate(req, res))) return;
    
    const limit = Math.min(parseInt(req.query.limit) || 200, 500);
    let alerts = await commerceStore.listDocuments('fraud_alerts', { orderBy: 'createdAt', direction: 'desc', limit: 1000 });
    if (req.query.resolved === 'false') alerts = alerts.filter((a) => a.resolved === false);
    alerts = alerts.slice(0, limit);
    res.json({ alerts });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ---- Admin MFA (TOTP) ------------------------------------------------------
// Enrollment is opt-in: an admin generates a secret, scans the QR in an
// authenticator app, then confirms with a valid code. Verification endpoints
// are provided here; enforcement in requireAdmin is intentionally NOT enabled
// yet (would lock out the existing secret-only panel). Enable enforcement only
// after the panel UI learns to send x-admin-totp.
const totp = require('../../services/totp');
const crypto = require('crypto');

function encryptSecret(plain) {
  const key = crypto.createHash('sha256').update(String(process.env.ENCRYPTION_KEY || process.env.ADMIN_SECRET || 'soko-vibe')).digest();
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const enc = Buffer.concat([cipher.update(plain, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return Buffer.concat([iv, tag, enc]).toString('base64');
}

function decryptSecret(blob) {
  const raw = Buffer.from(String(blob), 'base64');
  const iv = raw.slice(0, 12);
  const tag = raw.slice(12, 28);
  const enc = raw.slice(28);
  const key = crypto.createHash('sha256').update(String(process.env.ENCRYPTION_KEY || process.env.ADMIN_SECRET || 'soko-vibe')).digest();
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(enc), decipher.final()]).toString('utf8');
}

router.post('/mfa/enroll', async (req, res) => {
  try {
    const auth = await adminGate(req, res);
    if (!auth) return;
    const uid = auth.uid || 'admin-secret';
    const secret = totp.generateSecret();
    const account = uid === 'admin-secret' ? 'admin-secret' : uid;
    const uri = totp.otpauthUri({ secret, account });
    // Store as pending (not active) until verified.
    try {
      await commerceStore.updateDocument('users', uid, { 'mfa.pendingSecret': encryptSecret(secret) });
    } catch (_) { /* user doc may not exist for admin-secret */ }
    res.json({ success: true, secret, otpauthUri: uri });
  } catch (e) {
    console.error('[MFA][ENROLL]', e && e.message ? e.message : e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/mfa/verify', async (req, res) => {
  try {
    const auth = await adminGate(req, res);
    if (!auth) return;
    const uid = auth.uid || 'admin-secret';
    const code = req.body && req.body.code;
    const user = await commerceStore.getDocument('users', uid);
    const pending = user && user.mfa && user.mfa.pendingSecret;
    if (!pending) return res.status(400).json({ error: 'No pending enrollment' });
    const secret = decryptSecret(pending);
    if (!totp.verify(secret, code)) {
      return res.status(400).json({ error: 'Invalid code' });
    }
    await commerceStore.updateDocument('users', uid, {
      'mfa.secret': encryptSecret(secret),
      'mfa.enabled': true,
      'mfa.pendingSecret': null,
      'mfa.enrolledAt': commerceStore.serverTimestamp(),
    });
    clearAdminCache();
    res.json({ success: true, message: 'MFA enabled' });
  } catch (e) {
    console.error('[MFA][VERIFY]', e && e.message ? e.message : e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/mfa/disable', async (req, res) => {
  try {
    const auth = await adminGate(req, res);
    if (!auth) return;
    const uid = auth.uid || 'admin-secret';
    const code = req.body && req.body.code;
    const user = await commerceStore.getDocument('users', uid);
    const secretBlob = user && user.mfa && user.mfa.secret;
    if (user && user.mfa && user.mfa.enabled) {
      if (!secretBlob) return res.status(400).json({ error: 'MFA not configured' });
      const secret = decryptSecret(secretBlob);
      if (!totp.verify(secret, code)) return res.status(400).json({ error: 'Invalid code' });
    }
    await commerceStore.updateDocument('users', uid, {
      'mfa.secret': null,
      'mfa.enabled': false,
      'mfa.pendingSecret': null,
    });
    clearAdminCache();
    res.json({ success: true, message: 'MFA disabled' });
  } catch (e) {
    console.error('[MFA][DISABLE]', e && e.message ? e.message : e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Login-time TOTP check: called after the admin secret has been validated.
// Returns ok:true if MFA is disabled OR the supplied code is valid.
router.post('/mfa/login-check', async (req, res) => {
  try {
    const auth = await adminGate(req, res);
    if (!auth) return;
    const uid = auth.uid || 'admin-secret';
    const code = req.body && req.body.code;
    const user = await commerceStore.getDocument('users', uid);
    const enabled = !!(user && user.mfa && user.mfa.enabled && user.mfa.secret);
    if (!enabled) return res.json({ success: true, ok: true, mfaEnabled: false });
    let secret;
    try { secret = decryptSecret(user.mfa.secret); } catch (_) { return res.status(500).json({ error: 'MFA secret unreadable' }); }
    if (!totp.verify(secret, code)) return res.status(400).json({ success: false, ok: false, error: 'Invalid code' });
    res.json({ success: true, ok: true, mfaEnabled: true });
  } catch (e) {
    console.error('[MFA][LOGIN-CHECK]', e && e.message ? e.message : e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/mfa/status', async (req, res) => {
  try {
    const auth = await adminGate(req, res);
    if (!auth) return;
    const uid = auth.uid || 'admin-secret';
    const user = await commerceStore.getDocument('users', uid);
    const enabled = !!(user && user.mfa && user.mfa.enabled);
    res.json({ success: true, enabled, hasPending: !!(user && user.mfa && user.mfa.pendingSecret) });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
module.exports.publicRouter = publicRouter;
