const { getPrisma } = require('../../config/database');
const orderService = require('./order-service');
const paymentService = require('../payments/payment-service');
const handoverService = require('../handover/handover-service');

function asyncHandler(fn) {
  return (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);
}

// Order.sellerId refers to the SellerProfile row, so the acting seller's
// profile id must be resolved from their user id before any comparison.
async function resolveSellerProfile(prisma, userId) {
  const profile = await prisma.sellerProfile.findUnique({ where: { userId } });
  if (!profile) {
    const err = new Error('SELLER_PROFILE_NOT_FOUND');
    err.status = 403;
    throw err;
  }
  return profile;
}

const orderController = {
  createOrder: asyncHandler(async (req, res) => {
    const { productId, quantity, addressId } = req.body;
    const buyerId = req.user.id;

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
        seller: { select: { id: true, userId: true, storeName: true, logoUrl: true } },
        items: true,
        payments: true,
        shippingQuotes: true,
      },
    });

    if (!order) {
      return res.status(404).json({ success: false, error: 'ORDER_NOT_FOUND' });
    }

    // RBAC: only buyer, seller, or admin. Seller side compares the acting
    // user's SellerProfile id against order.sellerId.
    const isBuyer = order.buyerId === req.user.id;
    const isSeller = order.seller && order.seller.userId === req.user.id;
    const isAdmin = req.user.role === 'super_admin' || req.user.role === 'admin';

    if (!isBuyer && !isSeller && !isAdmin) {
      return res.status(403).json({ success: false, error: 'FORBIDDEN' });
    }

    res.json({ success: true, data: order });
  }),

  listOrders: asyncHandler(async (req, res) => {
    const prisma = getPrisma();
    const userId = req.user.id;
    const { status, role, page = 1, limit = 20, sort } = req.query;

    const profile = await prisma.sellerProfile.findUnique({ where: { userId } });
    const where = {
      OR: [
        { buyerId: userId },
        ...(profile ? [{ sellerId: profile.id }] : []),
      ],
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
        seller: { select: { id: true, userId: true, storeName: true, logoUrl: true } },
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
    const prisma = getPrisma();
    const profile = await resolveSellerProfile(prisma, req.user.id);
    const sellerId = profile.id;
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
    const approvedBy = req.user.id;

    const order = await orderService.approveShippingQuote({
      orderId,
      approvedBy,
    });

    res.json({ success: true, data: order });
  }),

  initiatePayment: asyncHandler(async (req, res) => {
    const { orderId } = req.params;
    const buyerId = req.user.id;
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
    const prisma = getPrisma();
    const profile = await resolveSellerProfile(prisma, req.user.id);
    const sellerId = profile.id;
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
    const actorId = req.user.id;

    const order = await orderService.markDelivered({
      orderId,
      actorId,
    });

    res.json({ success: true, data: order });
  }),

  // Complete the order ONLY through OTP verification (no bypass). This keeps
  // the escrow release gated on the buyer's handover credential.
  completeOrder: asyncHandler(async (req, res) => {
    const { orderId } = req.params;
    const { otp } = req.body;

    const result = await handoverService.verifyOtpAndComplete({
      orderId,
      submittedOtp: otp,
      verifiedBy: req.user.id,
    });

    res.json({ success: true, data: result });
  }),

  cancelOrder: asyncHandler(async (req, res) => {
    const { orderId } = req.params;
    const actorId = req.user.id;
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
    const filedBy = req.user.id;
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