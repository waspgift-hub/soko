const { Router } = require('express');
const { authenticateAdmin, requireActiveAdmin } = require('../../middleware/auth');
const { validate } = require('../../middleware/validation');
const { z } = require('zod');
const adminService = require('./admin-service');
const activity = require('../../services/activity');
const { getPrisma } = require('../../config/database');
const { getFirebaseFirestore } = require('../../config/firebase');
const { writeAudit, auditFromReq } = require('../../services/audit');

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
    const prisma = getPrisma();
    const before = await prisma.user.findUnique({
      where: { id: req.params.userId },
      select: { accountStatus: true, firebaseUid: true },
    });
    const user = await prisma.user.update({
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
    const prisma = getPrisma();
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
      prisma.order.findMany({
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
      prisma.order.count({ where }),
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
    const prisma = getPrisma();
    const where = req.query.status ? { status: req.query.status } : {};
    const [withdrawals, total] = await Promise.all([
      prisma.withdrawal.findMany({
        where,
        include: {
          seller: { select: { id: true, storeName: true, userId: true } },
          payouts: { orderBy: { createdAt: 'desc' }, take: 5 },
        },
        orderBy: { createdAt: 'desc' },
        take: Number(req.query.limit),
        skip: (Number(req.query.page) - 1) * Number(req.query.limit),
      }),
      prisma.withdrawal.count({ where }),
    ]);
    res.json({
      success: true,
      data: { withdrawals, pagination: { page: Number(req.query.page), limit: Number(req.query.limit), total } },
    });
  }
);

// Withdrawal status + payout attempts
router.get('/withdrawals/:id/status', async (req, res) => {
  const prisma = getPrisma();
  const withdrawal = await prisma.withdrawal.findUnique({
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
    const prisma = getPrisma();
    const current = await prisma.withdrawal.findUnique({ where: { id: req.params.id } });
    if (!current) return res.status(404).json({ error: 'WITHDRAWAL_NOT_FOUND' });
    if (current.status === 'completed') return res.status(409).json({ error: 'WITHDRAWAL_ALREADY_COMPLETED' });
    if (current.status === 'failed') {
      await prisma.withdrawal.update({
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
    const prisma = getPrisma();
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
      prisma.sellerProfile.findMany({
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
      prisma.sellerProfile.count({ where }),
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
    const prisma = getPrisma();
    const seller = await prisma.sellerProfile.findUnique({ where: { id: req.params.sellerId } });
    if (!seller) return res.status(404).json({ error: 'SELLER_NOT_FOUND' });
    const action = req.body.action;
    const data =
      action === 'verify'
        ? { verificationStatus: 'verified', sellerStatus: seller.sellerStatus === 'rejected' ? 'active' : seller.sellerStatus }
        : action === 'reject'
          ? { verificationStatus: 'rejected', sellerStatus: 'rejected' }
          : { verificationStatus: 'pending' };
    const updated = await prisma.sellerProfile.update({ where: { id: req.params.sellerId }, data });
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
    const prisma = getPrisma();
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
      prisma.product.findMany({
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
      prisma.product.count({ where }),
    ]);
    res.json({ success: true, data: { products, pagination: { page: Number(req.query.page), limit: Number(req.query.limit), total } } });
  }
);

// User detail for the panel drawer: profile + verification + storefront + wallet.
router.get(
  '/users/:userId',
  validate({ params: z.object({ userId: z.string().uuid() }) }),
  async (req, res) => {
    const prisma = getPrisma();
    const [user, buyerOrders, sellerOrders] = await Promise.all([
      prisma.user.findUnique({
        where: { id: req.params.userId },
        include: {
          sellerProfile: { include: { wallets: { orderBy: { createdAt: 'desc' }, take: 1 } } },
          devices: { select: { platform: true, appVersion: true, lastActiveAt: true }, take: 5 },
          addresses: { orderBy: { isDefault: 'desc' }, take: 10 },
        },
      }),
      prisma.order.groupBy({ by: ['status'], where: { buyerId: req.params.userId }, _count: { _all: true }, _sum: { totalAmount: true } }),
      prisma.order.groupBy({ by: ['status'], where: { seller: { userId: req.params.userId } }, _count: { status: true } }),
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
    const prisma = getPrisma();
    const where = req.query.status ? { status: req.query.status } : {};
    const [disputes, total] = await Promise.all([
      prisma.dispute.findMany({
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
      prisma.dispute.count({ where }),
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
    const prisma = getPrisma();
    const where = req.query.status ? { status: req.query.status } : {};
    const [refunds, total] = await Promise.all([
      prisma.refund.findMany({
        where,
        include: {
          order: { select: { id: true, orderNumber: true, totalAmount: true, status: true } },
          payment: { select: { id: true, provider: true, status: true, amount: true } },
        },
        orderBy: { createdAt: 'desc' },
        take: Number(req.query.limit),
        skip: (Number(req.query.page) - 1) * Number(req.query.limit),
      }),
      prisma.refund.count({ where }),
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
    const prisma = getPrisma();
    const where = req.query.status ? { status: req.query.status } : {};
    const [referrals, total] = await Promise.all([
      prisma.referral.findMany({
        where,
        include: {
          referrer: { select: { id: true, email: true, phone: true, displayName: true } },
          referred: { select: { id: true, email: true, phone: true, displayName: true } },
        },
        orderBy: { createdAt: 'desc' },
        take: Number(req.query.limit),
        skip: (Number(req.query.page) - 1) * Number(req.query.limit),
      }),
      prisma.referral.count({ where }),
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

module.exports = router;
