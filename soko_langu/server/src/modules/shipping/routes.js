const { Router } = require('express');
const { authenticate, requireActive } = require('../../middleware/auth');
const { validate } = require('../../middleware/validation');
const { z } = require('zod');
const shippingService = require('./shipping-quote-service');
const { getStore } = require('../../config/database');
const { syncLegacyOrderStatus } = require('../legacy-compat/presentation-mirror');

const router = Router();

// Publishes a quote-driven status change to the Firestore docs the app streams.
// Without this the store moves the order (e.g. to AWAITING_ESCROW_PAYMENT) but
// the `orders/{id}` doc the Flutter screen listens to keeps its old lowercase
// status — so an admin approves a quote and the buyer still sees "seller is
// quoting" and cannot reach payment. The v1 orders alias in order-service
// already mirrors; these routes call the service directly and bypass it.
async function mirrorQuoteOutcome(order) {
  if (!order || !order.id) return order;
  await syncLegacyOrderStatus(order);
  return order;
}

async function requireSellerProfile(req) {
  const store = getStore();
  const profile = await store.sellerProfile.findUnique({ where: { userId: req.user.id } });
  if (!profile) {
    const err = new Error('SELLER_PROFILE_NOT_FOUND');
    err.status = 403;
    throw err;
  }
  return profile;
}

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
    const profile = await requireSellerProfile(req);
    const result = await shippingService.submitQuote({
      orderId: req.params.orderId,
      sellerId: profile.id,
      amount: req.body.amount,
      estimatedDays: req.body.estimatedDays,
      notes: req.body.notes,
      shippingAddress: req.body.shippingAddress,
      sellerRegion: req.body.sellerRegion,
    });
    // Mirror 'quoted' + the server-locked shippingCost/totalAmount so the
    // buyer's invoice stops showing the creation-time zeros.
    await mirrorQuoteOutcome(result.updatedOrder);
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
      approvedBy: req.user.id,
    });
    await mirrorQuoteOutcome(order);
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
      blockedBy: req.user.id,
      reason: req.body.reason,
    });
    await mirrorQuoteOutcome(order);
    res.json({ success: true, data: order });
  }
);

module.exports = router;