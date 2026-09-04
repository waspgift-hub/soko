const { Router } = require('express');
const { authenticate, requireActive, verifyAdmin } = require('../../middleware/auth');
const { validate } = require('../../middleware/validation');
const { z } = require('zod');
const service = require('./referral-service');
const { writeAudit, auditFromReq } = require('../../services/audit');

const router = Router();

function serviceError(res, e) {
  return res.status(e.status || 500).json({ error: e.message || 'Referral operation failed' });
}

// My personal referral code (shareable)
router.get('/code', authenticate, requireActive, async (req, res) => {
  const data = await service.getMyCode({ userId: req.user.id });
  res.json({ success: true, data });
});

// Claim a referral with a friend's code
router.post(
  '/apply',
  authenticate,
  requireActive,
  validate({ body: z.object({ code: z.string().min(4).max(20) }) }),
  async (req, res) => {
    try {
      const referral = await service.applyReferral({ userId: req.user.id, code: req.body.code });
      res.status(201).json({ success: true, data: referral });
    } catch (e) {
      serviceError(res, e);
    }
  }
);

// My referrals (as referrer) + my status (as referred)
router.get('/mine', authenticate, requireActive, async (req, res) => {
  const data = await service.listMine({ userId: req.user.id });
  res.json({ success: true, data });
});

// Complete after qualifying action (admin/system)
router.post(
  '/:id/complete',
  authenticate,
  verifyAdmin,
  validate({
    body: z.object({
      qualifyingAction: z.string().max(50).optional(),
      rewardType: z.enum(['voucher', 'boost_credit', 'visibility_credit']).optional(),
      rewardAmount: z.number().int().min(0).optional(),
    }),
  }),
  async (req, res) => {
    try {
      const referral = await service.completeReferral({ id: req.params.id, ...req.body });
      await writeAudit({
        ...auditFromReq(req),
        action: 'referral.complete',
        entityType: 'referral',
        entityId: referral.id,
      });
      res.json({ success: true, data: referral });
    } catch (e) {
      serviceError(res, e);
    }
  }
);

module.exports = router;
