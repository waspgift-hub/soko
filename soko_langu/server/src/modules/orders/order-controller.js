const { getPrisma } = require('../../config/database');
const orderService = require('./order-service');
const paymentService = require('../payments/payment-service');

function asyncHandler(fn) {
  return (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);
}

const orderController = {
  createOrder: asyncHandler(async (req, res) => {
    const { productId, quantity, addressId } = req.body;
    const buyerId = req.user.uid;

    const order = await orderService.createOrder({
      buyerId,
      productId,
      quantity,
      addressId,
    });

    res.status(201).json({ success: true, data: order });
  }),

  getOrder: asyncHandler(async (req, res) => {
    const { orderId } = req.params;
    const prisma = getPrisma();

    const order = await prisma.order.findUnique({
      where: { id: orderId },
      include: {
        buyer: { select: { id: true, displayName: true, avatarUrl: true } },
        seller: { include: { seller: true } },
        items: true,
        payments: true,
        shippingQuote: true,
        dispute: true,
      },
    });

    if (!order) {
      return res.status(404).json({ success: false, error: 'ORDER_NOT_FOUND' });
    }

    // RBAC: only buyer, seller, or admin
    const isBuyer = order.buyerId === req.user.uid;
    const isSeller = order.sellerId === req.user.uid;
    const isAdmin = req.user.role === 'super_admin' || req.user.role === 'admin';

    if (!isBuyer && !isSeller && !isAdmin) {
      return res.status(403).json({ success: false, error: 'FORBIDDEN' });
    }

    res.json({ success: true, data: order });
  }),

  listOrders: asyncHandler(async (req, res) => {
    const prisma = getPrisma();
    const userId = req.user.uid;
    const { status, role, page = 1, limit = 20, sort } = req.query;

    const where = {
      OR: [{ buyerId: userId }, { sellerId: userId }],
    };

    if (status) {
      where.status = status;
    }

    const orders = await prisma.order.findMany({
      where,
      orderBy: { createdAt: sort === 'asc' ? 'asc' : 'desc' },
      take: Number(limit),
      skip: (Number(page) - 1) * Number(limit),
      include: {
        buyer: { select: { id: true, displayName: true, avatarUrl: true } },
        seller: { include: { seller: true } },
        items: true,
      },
    });

    const total = await prisma.order.count({ where });

    res.json({
      success: true,
      data: {
        orders,
        pagination: { page: Number(page), limit: Number(limit), total },
      },
    });
  }),

  submitShippingQuote: asyncHandler(async (req, res) => {
    const { orderId } = req.params;
    const sellerId = req.user.uid;
    const { amount, estimatedDays, notes } = req.body;

    const result = await orderService.submitShippingQuote({
      orderId,
      sellerId,
      amount,
      estimatedDays,
      notes,
    });

    res.status(201).json({ success: true, data: result });
  }),

  approveShippingQuote: asyncHandler(async (req, res) => {
    const { orderId } = req.params;
    const approvedBy = req.user.uid;

    const order = await orderService.approveShippingQuote({
      orderId,
      approvedBy,
    });

    res.json({ success: true, data: order });
  }),

  initiatePayment: asyncHandler(async (req, res) => {
    const { orderId } = req.params;
    const buyerId = req.user.uid;
    const { provider, amount, phoneNumber } = req.body;

    const result = await paymentService.initiatePayment({
      orderId,
      buyerId,
      provider,
      amount,
      phoneNumber,
    });

    res.status(201).json({ success: true, data: result });
  }),

  markDispatched: asyncHandler(async (req, res) => {
    const { orderId } = req.params;
    const sellerId = req.user.uid;
    const { courierName, trackingNumber } = req.body;

    const order = await orderService.markDispatched({
      orderId,
      sellerId,
      courierName,
      trackingNumber,
    });

    res.json({ success: true, data: order });
  }),

  markDelivered: asyncHandler(async (req, res) => {
    const { orderId } = req.params;
    const actorId = req.user.uid;

    const order = await orderService.markDelivered({
      orderId,
      actorId,
    });

    res.json({ success: true, data: order });
  }),

  completeOrder: asyncHandler(async (req, res) => {
    const { orderId } = req.params;
    const actorId = req.user.uid;
    const { otp, method } = req.body;

    // TODO: Verify OTP against stored handover code before completing
    const order = await orderService.completeOrder({
      orderId,
      actorId,
      method,
    });

    res.json({ success: true, data: order });
  }),

  cancelOrder: asyncHandler(async (req, res) => {
    const { orderId } = req.params;
    const actorId = req.user.uid;
    const { reason } = req.body;

    const order = await orderService.cancelOrder({
      orderId,
      actorId,
      reason,
    });

    res.json({ success: true, data: order });
  }),

  disputeOrder: asyncHandler(async (req, res) => {
    const { orderId } = req.params;
    const filedBy = req.user.uid;
    const { reason, description } = req.body;

    const dispute = await orderService.disputeOrder({
      orderId,
      filedBy,
      reason,
      description,
    });

    res.status(201).json({ success: true, data: dispute });
  }),
};

module.exports = orderController;
