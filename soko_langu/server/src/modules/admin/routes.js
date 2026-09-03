const { Router } = require('express');
const { authenticate, verifyAdmin, requireActive } = require('../../middleware/auth');
const { validate } = require('../../middleware/validation');
const { z } = require('zod');
const adminService = require('./admin-service');
const { getPrisma } = require('../../config/database');

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
    const user = await prisma.user.update({
      where: { id: req.params.userId },
      data: { accountStatus: req.body.accountStatus },
      select: { id: true, accountStatus: true, email: true },
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

module.exports = router;
