const { Router } = require('express');
const { authenticate, requireActive, verifyAdmin } = require('../../middleware/auth');
const { validate } = require('../../middleware/validation');
const { z } = require('zod');
const refundService = require('./refund-service');
const { writeAudit, auditFromReq } = require('../../services/audit');

const router = Router();

// Buyer or admin requests a refund on an escrow-funded order.
router.post(
  '/',
  authenticate,
  requireActive,
  validate({
    body: z.object({
      orderId: z.string().uuid(),
      reason: z.string().min(3).max(1000).optional(),
      amount: z.number().int().positive().optional(),
    }),
  }),
  async (req, res) => {
    const isAdmin = req.user.role === 'admin';
    const refund = await refundService.requestRefund({
      orderId: req.body.orderId,
      requestedBy: isAdmin ? req.body.requestedBy || req.user.id : req.user.id,
      role: isAdmin ? 'admin' : 'buyer',
      reason: req.body.reason,
      amount: req.body.amount,
    });
    if (!isAdmin) {
      await writeAudit({ ...auditFromReq(req), action: 'refund.request', entityType: 'refund', entityId: refund?.id, newState: { orderId: req.body.orderId } });
    }
    res.status(201).json({ success: true, data: refund });
  }
);

// Admin executes a pending/failed refund (releases escrow + disburses).
router.put(
  '/:refundId/process',
  authenticate,
  verifyAdmin,
  async (req, res) => {
    const result = await refundService.processRefund({
      refundId: req.params.refundId,
      processedBy: req.user.id,
    });
    await writeAudit({
      ...auditFromReq(req),
      action: 'refund.process',
      entityType: 'refund',
      entityId: req.params.refundId,
      newState: result.refund || result,
    });
    res.json({ success: true, data: result });
  }
);

// Refund history for an order (buyer/seller/admin).
router.get('/:orderId', authenticate, requireActive, async (req, res) => {
  const refunds = await refundService.listRefundsForOrder({
    orderId: req.params.orderId,
    requesterId: req.user.id,
    role: req.user.role,
  });
  res.json({ success: true, data: refunds });
});

module.exports = router;