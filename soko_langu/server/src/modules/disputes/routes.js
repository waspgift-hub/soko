const { Router } = require('express');
const { authenticate, requireActive } = require('../../middleware/auth');
const { validate } = require('../../middleware/validation');
const { z } = require('zod');
const disputeService = require('./dispute-service');
const evidenceService = require('./evidence-service');

const router = Router();

// File a dispute on an order
router.post(
  '/',
  authenticate,
  requireActive,
  validate({
    body: z.object({
      orderId: z.string().uuid(),
      reason: z.string().min(3).max(50),
      description: z.string().min(5).max(2000),
    }),
  }),
  async (req, res) => {
    const dispute = await disputeService.fileDispute({
      orderId: req.body.orderId,
      filedBy: req.user.uid,
      reason: req.body.reason,
      description: req.body.description,
      role: req.body.role,
    });
    res.status(201).json({ success: true, data: dispute });
  }
);

// Add evidence to a dispute
router.post(
  '/:disputeId/evidence',
  authenticate,
  requireActive,
  validate({
    body: z.object({
      type: z.string().min(3).max(30),
      r2Key: z.string().optional(),
      description: z.string().max(1000).optional(),
    }),
  }),
  async (req, res) => {
    const evidence = await evidenceService.addEvidence({
      disputeId: req.params.disputeId,
      submittedBy: req.user.uid,
      type: req.body.type,
      r2Key: req.body.r2Key,
      description: req.body.description,
    });
    res.status(201).json({ success: true, data: evidence });
  }
);

// List evidence for a dispute
router.get('/:disputeId/evidence', authenticate, requireActive, async (req, res) => {
  const evidence = await evidenceService.listEvidence({
    disputeId: req.params.disputeId,
    requesterId: req.user.uid,
  });
  res.json({ success: true, data: evidence });
});

// Resolve a dispute (admin)
router.put(
  '/:disputeId/resolve',
  authenticate,
  requireActive,
  validate({
    body: z.object({
      resolution: z.enum(['FULL_TO_SELLER', 'FULL_REFUND', 'PARTIAL']),
    }),
  }),
  async (req, res) => {
    const dispute = await disputeService.resolveDispute({
      disputeId: req.params.disputeId,
      resolvedBy: req.user.uid,
      resolution: req.body.resolution,
    });
    res.json({ success: true, data: dispute });
  }
);

module.exports = router;
