const { Router } = require('express');
const { authenticate, optionalAuth, requireActive } = require('../../middleware/auth');
const { validate } = require('../../middleware/validation');
const { z } = require('zod');
const orderController = require('./order-controller');

const router = Router();

// Buyer creates an order
router.post(
  '/',
  authenticate,
  requireActive,
  validate({
    body: z.object({
      productId: z.string().uuid(),
      quantity: z.number().int().min(1).max(99).default(1),
      addressId: z.string().uuid(),
    }),
  }),
  orderController.createOrder
);

// Buyer gets their order by id or order number
router.get('/:orderId', authenticate, orderController.getOrder);

// Buyer lists their orders
router.get('/', authenticate, orderController.listOrders);

// Seller submits a shipping quote
router.post(
  '/:orderId/shipping-quote',
  authenticate,
  requireActive,
  validate({
    body: z.object({
      amount: z.number().int().positive(),
      estimatedDays: z.number().int().min(1).max(60),
      notes: z.string().max(500).optional(),
    }),
  }),
  orderController.submitShippingQuote
);

// Admin approves shipping quote
router.post(
  '/:orderId/shipping-quote/approve',
  authenticate,
  requireActive,
  orderController.approveShippingQuote
);

// Buyer initiates payment
router.post(
  '/:orderId/payments/initiate',
  authenticate,
  requireActive,
  validate({
    body: z.object({
      provider: z.enum(['clickpesa', 'card', 'bank']),
      amount: z.number().int().positive(),
      phoneNumber: z.string().regex(/^\+?[0-9]{9,15}$/),
    }),
  }),
  orderController.initiatePayment
);

// Seller marks order as dispatched
router.post(
  '/:orderId/dispatch',
  authenticate,
  requireActive,
  validate({
    body: z.object({
      courierName: z.string().min(1).max(120),
      trackingNumber: z.string().min(1).max(120),
    }),
  }),
  orderController.markDispatched
);

// System/courier marks delivered
router.post(
  '/:orderId/delivered',
  authenticate,
  orderController.markDelivered
);

// Buyer confirms OTP (handover completes order)
router.post(
  '/:orderId/complete',
  authenticate,
  requireActive,
  validate({
    body: z.object({
      otp: z.string().length(6),
      method: z.enum(['otp', 'auto']).default('otp'),
    }),
  }),
  orderController.completeOrder
);

// Cancel order (buyer or seller)
router.post(
  '/:orderId/cancel',
  authenticate,
  requireActive,
  validate({
    body: z.object({
      reason: z.string().min(3).max(500),
    }),
  }),
  orderController.cancelOrder
);

// File a dispute
router.post(
  '/:orderId/dispute',
  authenticate,
  requireActive,
  validate({
    body: z.object({
      reason: z.string().min(3).max(200),
      description: z.string().min(5).max(2000),
    }),
  }),
  orderController.disputeOrder
);

module.exports = router;
