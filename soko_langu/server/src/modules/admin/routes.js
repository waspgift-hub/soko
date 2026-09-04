const { Router } = require('express');
const { authenticate, verifyAdmin, requireActive } = require('../../middleware/auth');
const { validate } = require('../../middleware/validation');
const { z } = require('zod');
const adminService = require('./admin-service');
const { getPrisma } = require('../../config/database');
const { writeAudit, auditFromReq } = require('../../services/audit');

const router = Router();

// All admin routes require both auth and admin role.
router.use(authenticate, verifyAdmin);

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
  requireActive,
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
      select: { accountStatus: true },
    });
    const user = await prisma.user.update({
      where: { id: req.params.userId },
      data: { accountStatus: req.body.accountStatus },
      select: { id: true, accountStatus: true, email: true },
    });
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

// Financial: list orders (with dispute/escrow status) for admin review
router.get(
  '/orders',
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
    const [orders, total] = await Promise.all([
      prisma.order.findMany({
        where,
        include: { items: true, escrowHold: true, dispute: true },
        orderBy: { createdAt: 'desc' },
        take: Number(req.query.limit),
        skip: (Number(req.query.page) - 1) * Number(req.query.limit),
      }),
      prisma.order.count({ where }),
    ]);
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

module.exports = router;
