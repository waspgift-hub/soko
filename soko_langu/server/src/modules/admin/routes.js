const { Router } = require('express');
const admin = require('firebase-admin');
const bcrypt = require('bcryptjs');
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
const cache = require('../../../cache');
const productStore = require('../products/product-store');
const crypto = require('crypto');

// A write to a product invalidates its detail entry by id and slug plus every
// filtered list, so a moderator delete never serves a stale catalog entry.
function invalidateProductCache(product) {
  const id = product?.id;
  const slug = product?.slug;
  if (id) cache.del(`catalog:product:v2:${id}`);
  if (slug) cache.del(`catalog:product:v2:${slug}`);
  cache.delPattern('catalog:list:v2:*');
}

const router = Router();

/**
 * Public read of the platform commission rate.
 *
 * Declared BEFORE `router.use(authenticateAdmin)` on purpose: a buyer must be
 * shown the rate they are charged before paying, so this cannot sit behind
 * admin auth — same reasoning that leaves `GET /config/ads` open. Nothing
 * secret is returned, only a percentage.
 *
 * The Flutter app caches this at startup and uses it in place of the previously
 * hardcoded 3.5%, which is how the app came to disagree with the server.
 */
router.get('/config/commission', async (req, res) => {
  try {
    const s = (await settingsService.getSettings()) || {};
    res.json({
      success: true,
      data: { platformCommissionPct: settingsService.commissionPercent(s) },
    });
  } catch (e) {
    // Must not block the client. It falls back to charging 0, which is the same
    // default the server charges when the rate is unknown.
    console.error('[config:commission] read failed:', e?.message || e);
    res.json({ success: true, data: { platformCommissionPct: 0 } });
  }
});

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

    // A suspension/deletion must kill live sessions at once: the 1h ID-token
    // window plus money-route gates are not enough for an actively abusive
    // account. requireFreshSession on money/admin routes enforces the stamp.
    if (user.firebaseUid && ['suspended', 'deleted'].includes(req.body.accountStatus)) {
      try {
        const { revokeUserSessions } = require('../../services/session-revocation');
        await revokeUserSessions(user.firebaseUid);
      } catch (e) {
        console.error('Session revocation failed for ' + user.firebaseUid + ':', e?.message || e);
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
      includeDeleted: z
        .enum(['0', '1'])
        .optional()
        .transform((v) => v === '1'),
    }),
  }),
  async (req, res) => {
    const store = getStore();
    // Deleted listings stay queryable: the panel has to be able to review what
    // was taken down, and `status=deleted` used to return nothing because the
    // deletedAt filter hid the very rows that filter asks for.
    const where = {
      ...(req.query.includeDeleted ? {} : { deletedAt: null }),
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
    res.json({
      success: true,
      data: {
        products,
        pagination: { page: Number(req.query.page), limit: Number(req.query.limit), total },
        includeDeleted: Boolean(req.query.includeDeleted),
      },
    });
  }
);

// Single product for the panel drawer. The list endpoint paginates, so scanning
// it for one id reported "not found" for anything past the first page.
router.get('/products/:id', async (req, res) => {
  const store = getStore();
  const product = await store.product.findUnique({
    where: { id: req.params.id },
    include: {
      seller: { select: { id: true, storeName: true, storeSlug: true } },
      category: { select: { id: true, name: true } },
      media: { select: { r2Key: true, thumbnailR2Key: true, type: true }, orderBy: { sortOrder: 'asc' } },
      boosts: { select: { plan: true, status: true, expiresAt: true }, orderBy: { createdAt: 'desc' }, take: 1 },
    },
  });
  if (!product) return res.status(404).json({ success: false, error: 'PRODUCT_NOT_FOUND' });
  res.json({ success: true, data: product });
});

// Moderator delete / restore. Soft only — see product-service.adminSetDeleted
// for why a hard delete would orphan orders and escrow rows.
router.delete(
  '/products/:id',
  validate({
    params: z.object({ id: z.string().min(1) }),
    body: z.object({ reason: z.string().max(500).optional() }),
  }),
  async (req, res) => {
    try {
      const product = await productStore.adminSetListingDeleted({
        productId: req.params.id,
        deleted: true,
      });
      invalidateProductCache(product);
      await writeAudit({
        ...auditFromReq(req),
        action: 'product.admin_delete',
        entityType: 'product',
        entityId: product.id,
        newState: { status: 'deleted', reason: req.body.reason || null },
      });
      res.json({ success: true, data: product });
    } catch (e) {
      res.status(e.status || 500).json({ success: false, error: e.message || 'DELETE_FAILED' });
    }
  }
);

router.post('/products/:id/restore', async (req, res) => {
  try {
    const product = await productStore.adminSetListingDeleted({
      productId: req.params.id,
      deleted: false,
    });
    invalidateProductCache(product);
    await writeAudit({
      ...auditFromReq(req),
      action: 'product.admin_restore',
      entityType: 'product',
      entityId: product.id,
      newState: { status: 'draft' },
    });
    res.json({ success: true, data: product });
  } catch (e) {
    res.status(e.status || 500).json({ success: false, error: e.message || 'RESTORE_FAILED' });
  }
});

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

// ---- Data-deletion web-form requests (public /data-deletion form) ----
// The public endpoint stores each submission in Firestore (dataDeletionRequests);
// these routes let the panel triage them (see privacy policy 7.2: 30-day
// cooling-off before permanent deletion) without touching the Firestore console.

// List submissions, newest first, optional status filter.
router.get(
  '/data-deletion-requests',
  validate({
    query: z.object({
      status: z.enum(['new', 'in_progress', 'resolved', 'rejected']).optional(),
      limit: z.coerce.number().int().min(1).max(500).default(100),
    }),
  }),
  async (req, res) => {
    const db = getFirebaseFirestore();
    if (!db) return res.status(503).json({ error: 'FIRESTORE_UNAVAILABLE' });
    const ref = db.collection('dataDeletionRequests');
    const snap = await ref.orderBy('createdAt', 'desc').limit(Number(req.query.limit)).get();
    let docs = snap.docs.map(fsDoc);
    if (req.query.status) docs = docs.filter((d) => d.status === req.query.status);
    try {
      const cnt = await ref.count().get();
      return res.json({ success: true, data: { items: docs, total: cnt.data().count } });
    } catch (e) {
      return res.json({ success: true, data: { items: docs, total: docs.length } });
    }
  }
);

// Dispatch path: mark a submission as being handled / done / rejected.
router.put(
  '/data-deletion-requests/:id/status',
  requireActiveAdmin,
  validate({
    body: z.object({
      status: z.enum(['new', 'in_progress', 'resolved', 'rejected']),
      note: z.string().max(500).optional(),
    }),
  }),
  async (req, res) => {
    const db = getFirebaseFirestore();
    if (!db) return res.status(503).json({ error: 'FIRESTORE_UNAVAILABLE' });
    const docRef = db.collection('dataDeletionRequests').doc(req.params.id);
    const before = await docRef.get();
    if (!before.exists) return res.status(404).json({ error: 'DATA_DELETION_REQUEST_NOT_FOUND' });
    const patch = { status: req.body.status, updatedAt: admin.firestore.FieldValue.serverTimestamp() };
    if (req.body.note != null && req.body.note.trim()) patch.note = req.body.note.trim();
    await docRef.set(patch, { merge: true });
    try {
      await writeAudit({
        ...auditFromReq(req),
        action: 'dataDeletionRequest.status.change',
        entityType: 'dataDeletionRequest',
        entityId: req.params.id,
        newState: req.body,
      });
    } catch (ae) {
      console.error('[admin:data-deletion] audit write skipped:', ae?.message || ae);
    }
    const after = await docRef.get();
    res.json({ success: true, data: fsDoc(after) });
  }
);

// ============================================================================
// STAFF MANAGEMENT (admin.sokovibe.co.tz — Wafanyakazi)
// Individual staff accounts with email + bcrypt-hashed password, role and
// permissions. Stored in Firestore `admin_staff` so the browser panel (and any
// future staff login surface) can read them without the ADMIN_SECRET shared
// secret being the only way in. Created/edited only through this panel by an
// authenticated admin (x-admin-secret or Firebase admin role).
// ============================================================================

const STAFF_COLL = 'admin_staff';
const SESSION_COLL = 'staff_sessions';
const SESSION_TTL_MS = 7 * 24 * 60 * 60 * 1000; // 7 days

const STAFF_ROLES = [
  { id: 'super_admin', label: 'Super Admin', perms: ['*'] },
  { id: 'admin', label: 'Admin', perms: ['users:*', 'orders:*', 'products:*', 'refunds:*', 'disputes:*', 'kyc:*', 'finance:*', 'settings:*', 'staff:*', 'audit:*'] },
  { id: 'moderator', label: 'Moderator', perms: ['disputes:*', 'refunds:*', 'products:moderate', 'kyc:*', 'users:read'] },
  { id: 'support', label: 'Support', perms: ['users:read', 'orders:read', 'broadcasts:send', 'landing:*'] },
  { id: 'finance', label: 'Finance', perms: ['withdrawals:*', 'finance:*', 'revenue:*', 'reconciliation:*', 'users:read'] },
];

function permsFor(role) {
  const r = STAFF_ROLES.find((x) => x.id === role);
  return r ? r.perms : [];
}
function roleLabel(role) {
  const r = STAFF_ROLES.find((x) => x.id === role);
  return r ? r.label : role;
}

function staffDb() {
  const db = getFirebaseFirestore();
  if (!db) throw Object.assign(new Error('FIRESTORE_UNAVAILABLE'), { status: 503 });
  return db;
}

/** Normalize + validate a staff email. */
function cleanEmail(v) {
  const e = String(v == null ? '' : v).trim().toLowerCase();
  if (!e || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e)) {
    throw Object.assign(new Error('INVALID_EMAIL'), { status: 400 });
  }
  return e;
}

/** Serialize a staff doc, never returning the password hash. */
function serializeStaff(doc) {
  const d = doc.data() || {};
  return {
    id: doc.id,
    email: d.email || '',
    name: d.name || '',
    role: d.role || 'support',
    permissions: Array.isArray(d.permissions) ? d.permissions : permsFor(d.role),
    active: d.active !== false,
    createdAt: d.createdAt && typeof d.createdAt.toDate === 'function' ? d.createdAt.toDate().toISOString() : d.createdAt || null,
    updatedAt: d.updatedAt && typeof d.updatedAt.toDate === 'function' ? d.updatedAt.toDate().toISOString() : d.updatedAt || null,
    createdBy: d.createdBy || null,
    lastLoginAt: d.lastLoginAt && typeof d.lastLoginAt.toDate === 'function' ? d.lastLoginAt.toDate().toISOString() : d.lastLoginAt || null,
  };
}

// List staff (with optional email/name search + pagination)
router.get(
  '/staff',
  validate({
    query: z.object({
      q: z.string().optional(),
      role: z.string().optional(),
      active: z.enum(['true', 'false']).optional(),
      page: z.coerce.number().int().min(1).default(1),
      limit: z.coerce.number().int().min(1).max(100).default(50),
    }),
  }),
  async (req, res) => {
    const db = staffDb();
    const { q, role, active, page, limit } = req.query;
    const p = Number(page);
    const l = Number(limit);
    let ref = db.collection(STAFF_COLL).orderBy('createdAt', 'desc');
    // Firestore: one equality filter + orderBy per query. Email uniqueness is
    // enforced at write time; search is done client-side over the fetched page
    // for simplicity (staff tables are small).
    const snap = await ref.get();
    let rows = snap.docs.map((d) => serializeStaff(d));
    if (role) rows = rows.filter((r) => r.role === role);
    if (active !== undefined) rows = rows.filter((r) => r.active === (active === 'true'));
    if (q) {
      const s = String(q).toLowerCase();
      rows = rows.filter((r) => r.email.includes(s) || r.name.toLowerCase().includes(s));
    }
    const total = rows.length;
    const start = (p - 1) * l;
    const pageRows = rows.slice(start, start + l);
    res.json({ success: true, data: { staff: pageRows, pagination: { page: p, limit: l, total, pages: Math.ceil(total / l) } } });
  }
);

// Create staff: email, password, name, role (+ optional custom permissions)
router.post(
  '/staff',
  requireActiveAdmin,
  validate({
    body: z.object({
      email: z.string().email(),
      password: z.string().min(8).max(128),
      name: z.string().min(1).max(120).optional().default(''),
      role: z.string().min(1).default('support'),
      permissions: z.array(z.string()).optional(),
    }),
  }),
  async (req, res) => {
    const db = staffDb();
    const email = cleanEmail(req.body.email);
    const role = STAFF_ROLES.some((r) => r.id === req.body.role) ? req.body.role : 'support';

    // Uniqueness: email must not already exist (any status).
    const byEmail = await db.collection(STAFF_COLL).where('email', '==', email).limit(1).get();
    if (!byEmail.empty) {
      return res.status(409).json({ success: false, error: 'EMAIL_EXISTS' });
    }

    const passwordHash = await bcrypt.hash(req.body.password, 10);
    const id = 'staff_' + crypto.randomUUID().replace(/-/g, '').slice(0, 22);
    const now = new Date().toISOString();
    const perms = Array.isArray(req.body.permissions) && req.body.permissions.length
      ? req.body.permissions
      : permsFor(role);

    const doc = {
      id, email, name: String(req.body.name || '').trim() || email.split('@')[0], role,
      permissions: perms, active: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: req.user?.id || 'admin-secret',
      passwordHash,
    };
    await db.collection(STAFF_COLL).doc(id).set(doc);
    await writeAudit({
      ...auditFromReq(req),
      action: 'staff.create',
      entityType: 'staff',
      entityId: id,
      newState: { email, role, name: doc.name },
    });
    res.status(201).json({ success: true, data: serializeStaff({ data: () => doc, id }) });
  }
);

// Update staff: role, permissions, active, name, password (optional)
router.put(
  '/staff/:id',
  requireActiveAdmin,
  validate({
    params: z.object({ id: z.string().min(1) }),
    body: z.object({
      email: z.string().email().optional(),
      password: z.string().min(8).max(128).optional(),
      name: z.string().min(1).max(120).optional(),
      role: z.string().optional(),
      permissions: z.array(z.string()).optional(),
      active: z.boolean().optional(),
    }),
  }),
  async (req, res) => {
    const db = staffDb();
    const ref = db.collection(STAFF_COLL).doc(req.params.id);
    const snap = await ref.get();
    if (!snap.exists) return res.status(404).json({ success: false, error: 'STAFF_NOT_FOUND' });
    const cur = snap.data() || {};

    const updates = { updatedAt: admin.firestore.FieldValue.serverTimestamp() };
    if (req.body.email !== undefined) {
      const email = cleanEmail(req.body.email);
      const dup = await db.collection(STAFF_COLL).where('email', '==', email).limit(1).get();
      const existsElsewhere = !dup.empty && dup.docs[0].id !== req.params.id;
      if (existsElsewhere) return res.status(409).json({ success: false, error: 'EMAIL_EXISTS' });
      updates.email = email;
    }
    if (req.body.password !== undefined) updates.passwordHash = await bcrypt.hash(req.body.password, 10);
    if (req.body.name !== undefined) updates.name = String(req.body.name).trim() || cur.name;
    if (req.body.role !== undefined) {
      if (!STAFF_ROLES.some((r) => r.id === req.body.role)) return res.status(400).json({ success: false, error: 'INVALID_ROLE' });
      updates.role = req.body.role;
      if (req.body.permissions === undefined) updates.permissions = permsFor(req.body.role);
    }
    if (req.body.permissions !== undefined) updates.permissions = req.body.permissions;
    if (req.body.active !== undefined) updates.active = !!req.body.active;

    await ref.set(updates, { merge: true });
    await writeAudit({
      ...auditFromReq(req),
      action: 'staff.update',
      entityType: 'staff',
      entityId: req.params.id,
      oldState: { email: cur.email, role: cur.role, active: cur.active },
      newState: updates,
    });
    const after = await ref.get();
    res.json({ success: true, data: serializeStaff(after) });
  }
);

// Delete staff (hard remove — audit record keeps history)
router.delete(
  '/staff/:id',
  requireActiveAdmin,
  validate({ params: z.object({ id: z.string().min(1) }) }),
  async (req, res) => {
    const db = staffDb();
    const ref = db.collection(STAFF_COLL).doc(req.params.id);
    const snap = await ref.get();
    if (!snap.exists) return res.status(404).json({ success: false, error: 'STAFF_NOT_FOUND' });
    const cur = snap.data() || {};
    // Never let an admin remove themselves while logged in via this panel.
    if (req.user && req.user.id === cur.createdBy) {
      return res.status(400).json({ success: false, error: 'CANNOT_REMOVE_SELF' });
    }
    await ref.delete();
    await writeAudit({
      ...auditFromReq(req),
      action: 'staff.delete',
      entityType: 'staff',
      entityId: req.params.id,
      oldState: { email: cur.email, role: cur.role },
    });
    res.json({ success: true, data: { id: req.params.id } });
  }
);

// Staff login: email + password -> short-lived session token
router.post(
  '/staff/login',
  validate({
    body: z.object({ email: z.string().email(), password: z.string().min(1) }),
  }),
  async (req, res) => {
    const db = staffDb();
    const email = String(req.body.email).trim().toLowerCase();
    const byEmail = await db.collection(STAFF_COLL).where('email', '==', email).limit(1).get();
    if (byEmail.empty) {
      return res.status(401).json({ success: false, error: 'INVALID_CREDENTIALS' });
    }
    const doc = byEmail.docs[0];
    const d = doc.data() || {};
    if (d.active === false) {
      return res.status(403).json({ success: false, error: 'STAFF_INACTIVE' });
    }
    const ok = await bcrypt.compare(req.body.password, d.passwordHash || '');
    if (!ok) {
      return res.status(401).json({ success: false, error: 'INVALID_CREDENTIALS' });
    }
    const token = crypto.randomBytes(24).toString('hex');
    const expiresAt = new Date(Date.now() + SESSION_TTL_MS);
    await db.collection(SESSION_COLL).doc(token).set({
      token, staffId: doc.id, email: d.email, role: d.role, name: d.name,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await doc.ref.update({ lastLoginAt: admin.firestore.FieldValue.serverTimestamp() });
    res.json({ success: true, data: { token, staff: { id: doc.id, email: d.email, name: d.name, role: d.role, permissions: d.permissions || permsFor(d.role) }, expiresAt: expiresAt.toISOString() } });
  }
);


/**
 * Send the official launch announcement to opted-in waitlist subscribers.
 * Runs in small batches so the admin request stays within the API timeout.
 */
router.post('/launch-waitlist/notify', requireActiveAdmin, async (req, res) => {
  const firestore = getFirebaseFirestore();
  if (!firestore) {
    return res.status(503).json({ success: false, error: 'Firestore is unavailable.' });
  }

  const allSubscribers = await firestore.collection('launch_waitlist')
    .where('status', '==', 'subscribed')
    .get();
  const pending = allSubscribers.docs.filter((doc) => {
    const data = doc.data();
    return !data.launchNotifiedAt && data.email;
  });
  const batch = pending.slice(0, 10);

  let sent = 0;
  let failed = 0;
  await Promise.all(batch.map(async (doc) => {
    const email = String(doc.data().email).trim();
    const html = '<div style="font-family:Arial,sans-serif;line-height:1.6;color:#17251d;max-width:600px;margin:auto">'
      + '<h1>SokoVibe imezinduliwa</h1>'
      + '<p>Habari,</p>'
      + '<p>Asante kwa kujiunga na orodha ya taarifa za SokoVibe. Tunafurahi kukujulisha kuwa marketplace yetu iko tayari.</p>'
      + '<p>Tembelea <a href="https://www.sokovibe.co.tz/">www.sokovibe.co.tz</a> kwa taarifa rasmi.</p>'
      + '<p style="font-size:12px;color:#68756c">Ulipokea ujumbe huu kwa sababu uliomba taarifa za uzinduzi. Kwa kuomba kuondolewa kwenye orodha, wasiliana na support@sokovibe.co.tz.</p>'
      + '</div>';

    try {
      const delivered = await sendMail(email, 'SokoVibe imezinduliwa', html);
      if (!delivered) {
        failed += 1;
        return;
      }
      await doc.ref.update({
        launchNotifiedAt: admin.firestore.FieldValue.serverTimestamp(),
        launchNotificationStatus: 'sent',
      });
      sent += 1;
    } catch (error) {
      failed += 1;
      console.error('[admin:launch-waitlist] delivery failed:', error.message);
    }
  }));

  res.json({
    success: true,
    processed: batch.length,
    sent,
    failed,
    remainingMayExist: pending.length > batch.length,
  });
});

module.exports = router;
