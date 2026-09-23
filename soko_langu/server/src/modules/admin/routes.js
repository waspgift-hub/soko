const { Router } = require('express');
const admin = require('firebase-admin');
const { authenticateAdmin, requireActiveAdmin } = require('../../middleware/auth');
const { validate } = require('../../middleware/validation');
const { z } = require('zod');
const adminService = require('./admin-service');
const settingsService = require('./settings-service');
const activity = require('../../services/activity');
const { getStore } = require('../../config/database');
const { getFirebaseFirestore } = require('../../config/firebase');
const { writeAudit, auditFromReq } = require('../../services/audit');
const { sendMail } = require('../../services/mailer');

const router = Router();

// All admin routes require admin access: a correct x-admin-secret alone, or
// strict Firebase auth + admin role (suspended/deleted stay blocked).
router.use(authenticateAdmin);

// Dashboard KPIs
router.get('/dashboard', async (req, res) => {
  const data = await adminService.getDashboard();
  res.json({ success: true, data });
});

// User management: search
router.get(
  '/users',
  validate({
    query: z.object({
      q: z.string().optional(),
      role: z.string().optional(),
      accountStatus: z.string().optional(),
      page: z.coerce.number().int().min(1).default(1),
      limit: z.coerce.number().int().min(1).max(100).default(20),
    }),
  }),
  async (req, res) => {
    const data = await adminService.searchUsers(req.query);
    res.json({ success: true, data });
  }
);

// User management: update account status (suspend/activate/delete marker)
router.put(
  '/users/:userId/status',
  requireActiveAdmin,
  validate({
    body: z.object({
      accountStatus: z.enum(['active', 'pending', 'suspended', 'deleted']),
      reason: z.string().max(500).optional(),
    }),
  }),
  async (req, res) => {
    const store = getStore();
    const before = await store.user.findUnique({
      where: { id: req.params.userId },
      select: { accountStatus: true, firebaseUid: true },
    });
    const user = await store.user.update({
      where: { id: req.params.userId },
      data: { accountStatus: req.body.accountStatus },
      select: { id: true, accountStatus: true, email: true, firebaseUid: true },
    });

    // Keep users/{firebaseUid}.isSuspended in sync: the app guards product
    // writes and BuyerRequests reads through Firestore rules which only check
    // this flag (notSuspended()). Without the sync, toggling the account to
    // "active" here would leave those Firestore operations still denied.
    if (user.firebaseUid && ['active', 'suspended'].includes(req.body.accountStatus)) {
      try {
        const fsDb = getFirebaseFirestore();
        if (fsDb) {
          await fsDb
            .collection('users')
            .doc(user.firebaseUid)
            .set({ isSuspended: req.body.accountStatus === 'suspended' }, { merge: true });
        }
      } catch (e) {
        console.error('Firestore isSuspended sync failed for ' + user.firebaseUid + ':', e?.message || e);
      }
    }

    await writeAudit({
      ...auditFromReq(req),
      action: 'user.status.change',
      entityType: 'user',
      entityId: req.params.userId,
      oldState: { accountStatus: before?.accountStatus || null },
      newState: { accountStatus: user.accountStatus, reason: req.body.reason || null },
    });
    res.json({ success: true, data: user });
  }
);

// Financial: list wallet ledger (reconciliation view)
router.get(
  '/ledger',
  validate({
    query: z.object({
      type: z.string().optional(),
      page: z.coerce.number().int().min(1).default(1),
      limit: z.coerce.number().int().min(1).max(100).default(50),
    }),
  }),
  async (req, res) => {
    const data = await adminService.listLedger(req.query);
    res.json({ success: true, data });
  }
);

// Financial: list orders (with dispute/escrow status) for admin review.
router.get(
  '/orders',
  validate({
    query: z.object({
      status: z.string().optional(),
      q: z.string().optional(),
      page: z.coerce.number().int().min(1).default(1),
      limit: z.coerce.number().int().min(1).max(100).default(20),
    }),
  }),
  async (req, res) => {
    const store = getStore();
    const where = {
      ...(req.query.status ? { status: req.query.status } : {}),
      ...(req.query.q
        ? {
            OR: [
              { orderNumber: { contains: req.query.q, mode: 'insensitive' } },
              { buyer: { email: { contains: req.query.q, mode: 'insensitive' } } },
              { buyer: { phone: { contains: req.query.q } } },
              { seller: { storeName: { contains: req.query.q, mode: 'insensitive' } } },
            ],
          }
        : {}),
    };
    const [orderRows, total] = await Promise.all([
      store.order.findMany({
        where,
        include: {
          buyer: { select: { id: true, email: true, phone: true, displayName: true } },
          seller: { select: { id: true, storeName: true, userId: true } },
          items: true,
          escrowHold: true,
          disputes: { select: { id: true, status: true, reason: true }, orderBy: { createdAt: 'desc' }, take: 1 },
        },
        orderBy: { createdAt: 'desc' },
        take: Number(req.query.limit),
        skip: (Number(req.query.page) - 1) * Number(req.query.limit),
      }),
      store.order.count({ where }),
    ]);
    // The panel shows one dispute per order: expose the latest as `dispute`.
    const orders = orderRows.map(({ disputes, ...o }) => ({ ...o, dispute: disputes[0] || null }));
    res.json({
      success: true,
      data: { orders, pagination: { page: Number(req.query.page), limit: Number(req.query.limit), total } },
    });
  }
);

// Platform metrics for dashboards (GMV, orders, payments, risk queues)
router.get('/metrics', async (req, res) => {
  const data = await adminService.getMetrics();
  res.json({ success: true, data });
});

// Audit log search (append-only; no update/delete endpoints exist)
router.get(
  '/audit-logs',
  validate({
    query: z.object({
      action: z.string().optional(),
      entityType: z.string().optional(),
      actorId: z.string().uuid().optional(),
      page: z.coerce.number().int().min(1).default(1),
      limit: z.coerce.number().int().min(1).max(100).default(50),
    }),
  }),
  async (req, res) => {
    const data = await adminService.listAuditLogs(req.query);
    res.json({ success: true, data });
  }
);

// ---- Withdrawals (admin operates real-money payouts) ----
const walletService = require('../wallet/wallet-service');

function withdrawalError(res, e) {
  return res.status(e.status || 500).json({ error: e.message || 'Withdrawal operation failed' });
}

// List withdrawals (default pending first)
router.get(
  '/withdrawals',
  validate({
    query: z.object({
      status: z.string().optional(),
      page: z.coerce.number().int().min(1).default(1),
      limit: z.coerce.number().int().min(1).max(100).default(20),
    }),
  }),
  async (req, res) => {
    const store = getStore();
    const where = req.query.status ? { status: req.query.status } : {};
    const [withdrawals, total] = await Promise.all([
      store.withdrawal.findMany({
        where,
        include: {
          seller: { select: { id: true, storeName: true, userId: true } },
          payouts: { orderBy: { createdAt: 'desc' }, take: 5 },
        },
        orderBy: { createdAt: 'desc' },
        take: Number(req.query.limit),
        skip: (Number(req.query.page) - 1) * Number(req.query.limit),
      }),
      store.withdrawal.count({ where }),
    ]);
    res.json({
      success: true,
      data: { withdrawals, pagination: { page: Number(req.query.page), limit: Number(req.query.limit), total } },
    });
  }
);

// Withdrawal status + payout attempts
router.get('/withdrawals/:id/status', async (req, res) => {
  const store = getStore();
  const withdrawal = await store.withdrawal.findUnique({
    where: { id: req.params.id },
    include: { payouts: { orderBy: { createdAt: 'desc' } } },
  });
  if (!withdrawal) return res.status(404).json({ error: 'WITHDRAWAL_NOT_FOUND' });
  res.json({ success: true, data: withdrawal });
});

// Process a pending withdrawal: sends the ClickPesa mobile-money payout.
router.post('/withdrawals/:id/process', async (req, res) => {
  try {
    const result = await walletService.processWithdrawal({
      withdrawalId: req.params.id,
      executedBy: req.user?.id || 'admin',
    });
    await writeAudit({
      ...auditFromReq(req),
      action: 'withdrawal.process',
      entityType: 'withdrawal',
      entityId: req.params.id,
      newState: { status: result.status, providerPayoutId: result.providerPayoutId || null },
    });
    res.json({ success: true, data: result });
  } catch (e) {
    withdrawalError(res, e);
  }
});

// Retry a failed withdrawal: resets to pending, then processes again.
router.post('/withdrawals/:id/retry', async (req, res) => {
  try {
    const store = getStore();
    const current = await store.withdrawal.findUnique({ where: { id: req.params.id } });
    if (!current) return res.status(404).json({ error: 'WITHDRAWAL_NOT_FOUND' });
    if (current.status === 'completed') return res.status(409).json({ error: 'WITHDRAWAL_ALREADY_COMPLETED' });
    if (current.status === 'failed') {
      await store.withdrawal.update({
        where: { id: req.params.id },
        data: { status: 'pending', providerPayoutId: null },
      });
    }
    const result = await walletService.processWithdrawal({
      withdrawalId: req.params.id,
      executedBy: req.user?.id || 'admin',
    });
    await writeAudit({
      ...auditFromReq(req),
      action: 'withdrawal.retry',
      entityType: 'withdrawal',
      entityId: req.params.id,
      newState: { status: result.status },
    });
    res.json({ success: true, data: result });
  } catch (e) {
    withdrawalError(res, e);
  }
});

// Confirm a payout completed (provider callback or manual confirmation).
router.post(
  '/withdrawals/:id/confirm',
  validate({ body: z.object({ providerPayoutId: z.string().optional() }) }),
  async (req, res) => {
    try {
      const result = await walletService.confirmPayout({
        withdrawalId: req.params.id,
        providerPayoutId: req.body?.providerPayoutId,
      });
      await writeAudit({
        ...auditFromReq(req),
        action: 'withdrawal.confirm',
        entityType: 'withdrawal',
        entityId: req.params.id,
        newState: { providerPayoutId: req.body?.providerPayoutId || null },
      });
      res.json({ success: true, data: result });
    } catch (e) {
      withdrawalError(res, e);
    }
  }
);

// ---- Admin list/detail endpoints for the browser panel (read-only unless
// stated). These keep the panel on the v2 Postgres engine as the source of
// truth instead of the Firestore mirrors. ----

// Sellers: every seller profile with its owner, wallet and traffic counters.
router.get(
  '/sellers',
  validate({
    query: z.object({
      q: z.string().optional(),
      verificationStatus: z.string().optional(),
      sellerStatus: z.string().optional(),
      page: z.coerce.number().int().min(1).default(1),
      limit: z.coerce.number().int().min(1).max(100).default(20),
    }),
  }),
  async (req, res) => {
    const store = getStore();
    const where = {
      ...(req.query.q
        ? {
            OR: [
              { storeName: { contains: req.query.q, mode: 'insensitive' } },
              { storeSlug: { contains: req.query.q, mode: 'insensitive' } },
              { user: { email: { contains: req.query.q, mode: 'insensitive' } } },
              { user: { phone: { contains: req.query.q } } },
            ],
          }
        : {}),
      ...(req.query.verificationStatus ? { verificationStatus: req.query.verificationStatus } : {}),
      ...(req.query.sellerStatus ? { sellerStatus: req.query.sellerStatus } : {}),
    };
    const [sellerRows, total] = await Promise.all([
      store.sellerProfile.findMany({
        where,
        include: {
          user: { select: { id: true, email: true, phone: true, displayName: true, avatarUrl: true, accountStatus: true } },
          wallets: { select: { availableBalance: true, pendingBalance: true, frozenBalance: true, totalEarned: true, totalWithdrawn: true, status: true }, orderBy: { createdAt: 'desc' }, take: 1 },
          _count: { select: { products: true, orders: true, withdrawals: true } },
        },
        orderBy: { createdAt: 'desc' },
        take: Number(req.query.limit),
        skip: (Number(req.query.page) - 1) * Number(req.query.limit),
      }),
      store.sellerProfile.count({ where }),
    ]);
    // sellerId is unique on wallets: expose the single wallet as `wallet`.
    const sellers = sellerRows.map(({ wallets, ...s }) => ({ ...s, wallet: wallets[0] || null }));
    res.json({ success: true, data: { sellers, pagination: { page: Number(req.query.page), limit: Number(req.query.limit), total } } });
  }
);

// Seller verification: approve / reject / reset a storefront. Only touches the
// v2 profile (Postgres); the Firestore KYC mirror stays on legacy endpoints.
router.put(
  '/sellers/:sellerId/verification',
  validate({
    body: z.object({
      action: z.enum(['verify', 'reject', 'pending']),
    }),
  }),
  async (req, res) => {
    const store = getStore();
    const seller = await store.sellerProfile.findUnique({ where: { id: req.params.sellerId } });
    if (!seller) return res.status(404).json({ error: 'SELLER_NOT_FOUND' });
    const action = req.body.action;
    const data =
      action === 'verify'
        ? { verificationStatus: 'verified', sellerStatus: seller.sellerStatus === 'rejected' ? 'active' : seller.sellerStatus }
        : action === 'reject'
          ? { verificationStatus: 'rejected', sellerStatus: 'rejected' }
          : { verificationStatus: 'pending' };
    const updated = await store.sellerProfile.update({ where: { id: req.params.sellerId }, data });
    await writeAudit({
      ...auditFromReq(req),
      action: 'seller.verification',
      entityType: 'seller_profile',
      entityId: req.params.sellerId,
      oldState: { verificationStatus: seller.verificationStatus, sellerStatus: seller.sellerStatus },
      newState: data,
    });
    res.json({ success: true, data: updated });
  }
);

// Products: every product (any status) with store + category + first media.
router.get(
  '/products',
  validate({
    query: z.object({
      q: z.string().optional(),
      status: z.string().optional(),
      categoryId: z.string().optional(),
      page: z.coerce.number().int().min(1).default(1),
      limit: z.coerce.number().int().min(1).max(100).default(20),
    }),
  }),
  async (req, res) => {
    const store = getStore();
    const where = {
      deletedAt: null,
      ...(req.query.q
        ? {
            OR: [
              { title: { contains: req.query.q, mode: 'insensitive' } },
              { slug: { contains: req.query.q, mode: 'insensitive' } },
            ],
          }
        : {}),
      ...(req.query.status ? { status: req.query.status } : {}),
      ...(req.query.categoryId ? { categoryId: req.query.categoryId } : {}),
    };
    const [products, total] = await Promise.all([
      store.product.findMany({
        where,
        include: {
          seller: { select: { id: true, storeName: true, storeSlug: true } },
          category: { select: { id: true, name: true } },
          media: { select: { r2Key: true, thumbnailR2Key: true, type: true }, orderBy: { sortOrder: 'asc' } },
          boosts: { select: { plan: true, status: true, expiresAt: true }, orderBy: { createdAt: 'desc' }, take: 1 },
        },
        orderBy: { createdAt: 'desc' },
        take: Number(req.query.limit),
        skip: (Number(req.query.page) - 1) * Number(req.query.limit),
      }),
      store.product.count({ where }),
    ]);
    res.json({ success: true, data: { products, pagination: { page: Number(req.query.page), limit: Number(req.query.limit), total } } });
  }
);

// User detail for the panel drawer: profile + verification + storefront + wallet.
router.get(
  '/users/:userId',
  validate({ params: z.object({ userId: z.string().uuid() }) }),
  async (req, res) => {
    const store = getStore();
    const [user, buyerOrders, sellerOrders] = await Promise.all([
      store.user.findUnique({
        where: { id: req.params.userId },
        include: {
          sellerProfile: { include: { wallets: { orderBy: { createdAt: 'desc' }, take: 1 } } },
          devices: { select: { platform: true, appVersion: true, lastActiveAt: true }, take: 5 },
          addresses: { orderBy: { isDefault: 'desc' }, take: 10 },
        },
      }),
      store.order.groupBy({ by: ['status'], where: { buyerId: req.params.userId }, _count: { _all: true }, _sum: { totalAmount: true } }),
      store.order.groupBy({ by: ['status'], where: { seller: { userId: req.params.userId } }, _count: { status: true } }),
    ]);
    if (!user) return res.status(404).json({ error: 'USER_NOT_FOUND' });
    if (user.sellerProfile) {
      const { wallets, ...sp } = user.sellerProfile;
      user.sellerProfile = { ...sp, wallet: wallets[0] || null };
    }
    res.json({ success: true, data: { user, buyerOrders, sellerOrders } });
  }
);

// Disputes across the platform (open → under_review → resolved).
router.get(
  '/disputes',
  validate({
    query: z.object({
      status: z.string().optional(),
      page: z.coerce.number().int().min(1).default(1),
      limit: z.coerce.number().int().min(1).max(100).default(20),
    }),
  }),
  async (req, res) => {
    const store = getStore();
    const where = req.query.status ? { status: req.query.status } : {};
    const [disputes, total] = await Promise.all([
      store.dispute.findMany({
        where,
        include: {
          order: { select: { id: true, orderNumber: true, totalAmount: true, status: true } },
          filer: { select: { id: true, email: true, phone: true, displayName: true } },
          evidence: { select: { id: true, type: true, description: true, createdAt: true } },
        },
        orderBy: { createdAt: 'desc' },
        take: Number(req.query.limit),
        skip: (Number(req.query.page) - 1) * Number(req.query.limit),
      }),
      store.dispute.count({ where }),
    ]);
    res.json({ success: true, data: { disputes, pagination: { page: Number(req.query.page), limit: Number(req.query.limit), total } } });
  }
);

// Refunds across the platform (pending → processing → completed/failed).
router.get(
  '/refunds',
  validate({
    query: z.object({
      status: z.string().optional(),
      page: z.coerce.number().int().min(1).default(1),
      limit: z.coerce.number().int().min(1).max(100).default(20),
    }),
  }),
  async (req, res) => {
    const store = getStore();
    const where = req.query.status ? { status: req.query.status } : {};
    const [refunds, total] = await Promise.all([
      store.refund.findMany({
        where,
        include: {
          order: { select: { id: true, orderNumber: true, totalAmount: true, status: true } },
          payment: { select: { id: true, provider: true, status: true, amount: true } },
        },
        orderBy: { createdAt: 'desc' },
        take: Number(req.query.limit),
        skip: (Number(req.query.page) - 1) * Number(req.query.limit),
      }),
      store.refund.count({ where }),
    ]);
    res.json({ success: true, data: { refunds, pagination: { page: Number(req.query.page), limit: Number(req.query.limit), total } } });
  }
);

// Referrals for reward review (pending → complete).
router.get(
  '/referrals',
  validate({
    query: z.object({
      status: z.string().optional(),
      page: z.coerce.number().int().min(1).default(1),
      limit: z.coerce.number().int().min(1).max(100).default(20),
    }),
  }),
  async (req, res) => {
    const store = getStore();
    const where = req.query.status ? { status: req.query.status } : {};
    const [referrals, total] = await Promise.all([
      store.referral.findMany({
        where,
        include: {
          referrer: { select: { id: true, email: true, phone: true, displayName: true } },
          referred: { select: { id: true, email: true, phone: true, displayName: true } },
        },
        orderBy: { createdAt: 'desc' },
        take: Number(req.query.limit),
        skip: (Number(req.query.page) - 1) * Number(req.query.limit),
      }),
      store.referral.count({ where }),
    ]);
    res.json({ success: true, data: { referrals, pagination: { page: Number(req.query.page), limit: Number(req.query.limit), total } } });
  }
);

// Orders: allow quick lookup by order number / buyer contact alongside the
// status filter the existing endpoint already supports.

// ---- Usage analytics (Redis request tracker + lastLoginAt actives) ----
// Active users, rolling windows: day = 24h, week = 7d, month = 30d, year = 365d.
router.get('/analytics/active', async (req, res) => {
  const data = await activity.getActiveStats();
  res.json({ success: true, data });
});
// Request totals per bucket + distinct actives + avg requests per active user.
router.get(
  '/analytics/requests',
  validate({ query: z.object({ granularity: z.enum(['min', 'hour', 'day', 'month', 'year']).default('day') }) }),
  async (req, res) => {
    const data = await activity.getRequestSeries(req.query.granularity);
    res.json({ success: true, data });
  }
);
// Top users by request count over the last N days.
router.get(
  '/analytics/users/top',
  validate({
    query: z.object({
      days: z.coerce.number().int().min(1).max(365).default(7),
      limit: z.coerce.number().int().min(1).max(50).default(20),
    }),
  }),
  async (req, res) => {
    const data = await activity.getTopUsers(req.query.days, req.query.limit);
    res.json({ success: true, data });
  }
);

// ---- Platform settings (admin "Mipangilio") ----
// Masked read (secrets stay server-side; SECRET_FIELDS are returned as
// '******' so the SPA bundle never receives gateway/SMTP credentials).
router.get('/settings', async (req, res, next) => {
  try {
    const masked = await settingsService.getSettingsMasked();
    res.json({ success: true, data: masked });
  } catch (e) {
    console.error('[admin:settings] masked read failed:', e?.message || e);
    next(e);
  }
});

// Merge a partial map of groups/keys over current settings.
// Any key not present in DEFAULTS is rejected inside safeMerge.
router.put(
  '/settings',
  validate({
    body: z.object({
      patch: z.record(z.string(), z.any()).optional().default({}),
    }),
  }),
  async (req, res, next) => {
    try {
      await settingsService.saveSettings(req.body?.patch || {});
      const masked = await settingsService.getSettingsMasked();
      try {
        await writeAudit({
          ...auditFromReq(req),
          action: 'settings_update',
          entityType: 'settings',
          entityId: 'admin_settings',
          reason: 'Admin updated platform settings',
        });
      } catch (ae) {
        // Audit stays best-effort: a ledger hiccup must never fail a settings
        // save that already succeeded.
        console.error('[admin:settings] audit write skipped:', ae?.message || ae);
      }
      res.json({ success: true, data: masked });
    } catch (e) {
      console.error('[admin:settings] save failed:', e?.message || e);
      res.status(500).json({
        success: false,
        error: (e && e.message) || 'Kuna hitilafu ya ndani wakati wa kuhifadhi mipangilio.',
      });
    }
  }
);

// ---- Landing (coming-soon) submissions + waitlist email broadcast ----
// Everything collected on www.sokovibe.co.tz lives in Firestore
// (landing_waitlist / landing_feature_suggestions / landing_comments), so the
// browser panel reads it with the server's admin SDK instead of opening rules.

function fsDoc(d) {
  const data = d.data() || {};
  const out = { id: d.id };
  for (const k of Object.keys(data)) {
    // Timestamps serialize as ISO so the panel renders dates without a client SDK.
    out[k] = data[k] && typeof data[k].toDate === 'function' ? data[k].toDate().toISOString() : data[k];
  }
  return out;
}

async function landingSnapshot(db, collectionName, limit) {
  const ref = db.collection(collectionName);
  const [snap, cnt] = await Promise.all([
    ref.orderBy('createdAt', 'desc').limit(limit).get(),
    ref.count().get(),
  ]);
  return { items: snap.docs.map(fsDoc), total: cnt.data().count };
}

// Overview: waitlist subscribers, feature suggestions and public comments.
router.get('/landing', async (req, res) => {
  const db = getFirebaseFirestore();
  if (!db) return res.status(503).json({ error: 'FIRESTORE_UNAVAILABLE' });
  const [waitlist, suggestions, comments] = await Promise.all([
    landingSnapshot(db, 'landing_waitlist', 500),
    landingSnapshot(db, 'landing_feature_suggestions', 200),
    landingSnapshot(db, 'landing_comments', 100),
  ]);
  res.json({ success: true, data: { waitlist, suggestions, comments } });
});

// Broadcast an email to every waitlist subscriber ("the app is ready").
// Sends through the existing SMTP mailer with bounded concurrency so Gmail's
// per-hour send limit is never hammered all at once.
router.post(
  '/landing/broadcast',
  requireActiveAdmin,
  validate({
    body: z.object({
      subject: z.string().min(3).max(150),
      body: z.string().min(3).max(5000),
    }),
  }),
  async (req, res) => {
    const db = getFirebaseFirestore();
    if (!db) return res.status(503).json({ error: 'FIRESTORE_UNAVAILABLE' });
    if (!process.env.SMTP_USER || !process.env.SMTP_PASS) {
      return res.status(503).json({ error: 'SMTP haijasanidiwa (weka SMTP_USER/SMTP_PASS).' });
    }

    const snap = await db.collection('landing_waitlist').get();
    const entries = snap.docs.map(fsDoc);
    const byEmail = {};
    const emails = [];
    for (const e of entries) {
      const em = String(e.email || '').trim().toLowerCase();
      if (!em || byEmail[em]) continue;
      byEmail[em] = e;
      emails.push(em);
    }
    if (!emails.length) {
      return res.json({ success: true, data: { total: 0, sent: 0, failed: 0 } });
    }

    const escapeHtml = (v) =>
      String(v == null ? '' : v).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

    const htmlFor = (email, body) => {
      const name = byEmail[email] && byEmail[email].name ? String(byEmail[email].name).split(' ')[0] : '';
      const greet = name ? 'Habari ' + escapeHtml(name) + ',' : 'Habari,';
      return (
        '<!doctype html><html><body style="margin:0;background:#f4f0ee;font-family:Segoe UI,Arial,sans-serif">' +
        '<div style="max-width:560px;margin:24px auto;background:#ffffff;border-radius:16px;overflow:hidden;border:1px solid #e7dddd">' +
        '<div style="padding:20px 28px;background:linear-gradient(120deg,#5a44e8,#c0004c,#e07900);color:#fff;font-size:20px;font-weight:800;letter-spacing:-.02em">Soko Vibe</div>' +
        '<div style="padding:28px;color:#201a1b;line-height:1.6">' +
        '<p style="margin:0 0 14px">' + greet + '</p>' +
        '<div style="white-space:pre-line">' + escapeHtml(body) + '</div>' +
        '<p style="margin:26px 0 0;color:#6f6768;font-size:13px">Soko Vibe — dinasikiliza maoni yako.<br>' +
        'Hutaki kupokea ujumbe huu tena? Tujibu na barua hii tutakuondoa kwenye orodha.</p>' +
        '</div></div></body></html>'
      );
    };

    const CONCURRENCY = 5;
    let cursor = 0, sent = 0, failed = 0;
    const workers = Array.from({ length: CONCURRENCY }, async () => {
      while (true) {
        const i = cursor++;
        if (i >= emails.length) break;
        const ok = await sendMail(emails[i], req.body.subject, htmlFor(emails[i], req.body.body));
        if (ok) sent++; else failed++;
      }
    });
    await Promise.all(workers);

    try {
      await writeAudit({
        ...auditFromReq(req),
        action: 'landing.broadcast',
        entityType: 'landing_waitlist',
        entityId: 'broadcast',
        newState: { subject: req.body.subject, total: emails.length, sent, failed },
      });
    } catch (ae) {
      console.error('[admin:landing] audit write skipped:', ae?.message || ae);
    }
    try {
      await db.collection('landing_broadcasts').add({
        subject: req.body.subject,
        body: req.body.body,
        total: emails.length,
        sent,
        failed,
        executedBy: req.user?.id || 'admin',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (ce) {
      console.error('[admin:landing] broadcast log write failed:', ce?.message || ce);
    }

    res.json({ success: true, data: { total: emails.length, sent, failed } });
  }
);

module.exports = router;
