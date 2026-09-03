const { Router } = require('express');
const { authenticate, requireActive } = require('../../middleware/auth');
const { validate } = require('../../middleware/validation');
const { z } = require('zod');
const walletService = require('./wallet-service');

const router = Router();

// Get seller wallet + ledger (requires seller role)
router.get('/', authenticate, requireActive, async (req, res) => {
  const detail = await walletService.getWalletDetail(req.user.uid, {
    page: req.query.page,
    limit: req.query.limit,
  });
  res.json({ success: true, data: detail });
});

// Request a withdrawal
router.post(
  '/withdrawals',
  authenticate,
  requireActive,
  validate({
    body: z.object({
      amount: z.number().int().positive(),
      phoneNumber: z.string().regex(/^\+?[0-9]{9,15}$/).optional(),
    }),
  }),
  async (req, res) => {
    const result = await walletService.requestWithdrawal({
      sellerId: req.user.uid,
      amount: req.body.amount,
      phoneNumber: req.body.phoneNumber,
    });
    res.status(201).json({ success: true, data: result });
  }
);

// List withdrawal history
router.get('/withdrawals', authenticate, requireActive, async (req, res) => {
  const prisma = require('../../config/database').getPrisma();
  const withdrawals = await prisma.withdrawal.findMany({
    where: { sellerId: req.user.uid },
    orderBy: { createdAt: 'desc' },
  });
  res.json({ success: true, data: withdrawals });
});

module.exports = router;
