const { Router } = require('express');
const { authenticate, requireActive } = require('../../middleware/auth');
const { validate } = require('../../middleware/validation');
const { z } = require('zod');
const shippingService = require('./shipping-quote-service');

const router = Router();

// Seller submits a shipping quote for an order
router.post(
  '/:orderId/quote',
  authenticate,
  requireActive,
  validate({
    body: z.object({
      amount: z.number().int().positive().max(5000000),
      estimatedDays: z.number().int().min(1).max(60),
      notes: z.string().max(500).optional(),
    }),
  }),
  async (req, res) => {
    const result = await shippingService.submitQuote({
      orderId: req.params.orderId,
      sellerId: req.user.uid,
      amount: req.body.amount,
      estimatedDays: req.body.estimatedDays,
      notes: req.body.notes,
      shippingAddress: req.body.shippingAddress,
      sellerRegion: req.body.sellerRegion,
    });
    res.status(201).json({ success: true, data: result });
  }
);

// Admin approves a quote -> moves order to await payment
router.post(
  '/:orderId/quote/approve',
  authenticate,
  requireActive,
  async (req, res) => {
    const order = await shippingService.approveQuote({
      orderId: req.params.orderId,
      approvedBy: req.user.uid,
    });
    res.json({ success: true, data: order });
  }
);

// Admin blocks a quote -> returns order to fee submission
router.post(
  '/:orderId/quote/block',
  authenticate,
  requireActive,
  validate({
    body: z.object({ reason: z.string().min(3).max(500) }),
  }),
  async (req, res) => {
    const order = await shippingService.blockQuote({
      orderId: req.params.orderId,
      blockedBy: req.user.uid,
      reason: req.body.reason,
    });
    res.json({ success: true, data: order });
  }
);

module.exports = router;
