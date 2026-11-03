const { Router } = require('express');
const { authenticate, requireActive } = require('../../middleware/auth');
const { validate } = require('../../middleware/validation');
const { z } = require('zod');
const { getPrisma } = require('../../config/database');
const walletService = require('./wallet-service');

const router = Router();

// Resolve the caller's SellerProfile (wallet owner). Wallets belong to
// SellerProfile rows, not directly to users.
async function requireSellerProfile(userId) {
  const prisma = getPrisma();
  const profile = await prisma.sellerProfile.findUnique({
    where: { userId },
    select: { id: true },
  });
  if (!profile) {
    const err = new Error('SELLER_PROFILE_NOT_FOUND');
    err.status = 404;
    throw err;
  }
  return profile;
}

// Get seller wallet + ledger (requires seller role)
router.get('/', authenticate, requireActive, async (req, res) => {
  const profile = await requireSellerProfile(req.user.id);
  const detail = await walletService.getWalletDetail(profile.id, {
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
    const profile = await requireSellerProfile(req.user.id);
    const result = await walletService.requestWithdrawal({
      sellerId: profile.id,
      amount: req.body.amount,
      phoneNumber: req.body.phoneNumber,
    });
    res.status(201).json({ success: true, data: result });
  }
);

// List withdrawal history
router.get('/withdrawals', authenticate, requireActive, async (req, res) => {
  const prisma = getPrisma();
  const profile = await requireSellerProfile(req.user.id);
  const withdrawals = await prisma.withdrawal.findMany({
    where: { sellerId: profile.id },
    orderBy: { createdAt: 'desc' },
  });
  res.json({ success: true, data: withdrawals });
});

module.exports = router;
