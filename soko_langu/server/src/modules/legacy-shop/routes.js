// Legacy web-shop compat: serves the shop SPA's existing endpoints with the
// SAME response shapes, but executes against the v2 Postgres order/pay engine
// (BigInt escrow, ClickPesa v2 webhook, OTP-gated release). Buyers are
// entity-synced on first authenticated request so legacy Firebase users get a
// users row (the v2 `users` table previously held only admins).
const { Router } = require('express');
const { getPrisma } = require('../../config/database');
const { getFirebaseAuth } = require('../../config/firebase');
const { optionalAuth } = require('../../middleware/auth');
const { paymentService } = require('../payments/payment-service');
const { generateOrderNumber } = require('../orders/order-service');
const { ORDER_STATES } = require('../orders/order-state-machine');

function httpError(status, message) {
  const err = new Error(message);
  err.status = status;
  return err;
}

const LEGACY_STATUS = {
  payment_pending: 'pending',
  pending_shipping_fee: 'pending',
  awaiting_escrow_payment: 'pending',
  in_escrow: 'escrow_hold',
  ready_to_dispatch: 'escrow_hold',
  dispatched: 'dispatched',
  in_transit: 'dispatched',
  out_for_delivery: 'dispatched',
  delivery_attempted: 'delivered',
  delivered: 'delivered',
  inspection_period: 'delivered',
  otp_pending: 'delivered',
  completed: 'completed',
  wallet_credited: 'completed',
  payout_pending: 'completed',
  payout_complete: 'completed',
  disputed: 'disputed',
  refund_pending: 'refunded',
  refunded: 'refunded',
  cancelled: 'cancelled',
  failed: 'failed',
  expired: 'failed',
  draft: 'pending',
  published: 'pending',
  address_required: 'pending',
  shipping_fee_submitted: 'pending',
  shipping_fee_review: 'pending',
};

function slugSuffix() {
  return Math.random().toString(36).slice(2, 8);
}

// Attach/sync the shop buyer into the v2 `users` table from Firebase Auth.
async function requireSyncedBuyer(req, res, next) {
  const uid = req.firebaseUid;
  if (!uid) return res.status(401).json({ error: 'AUTH_REQUIRED' });
  try {
    if (!req.user) {
      const prisma = getPrisma();
      const auth = getFirebaseAuth();
      const rec = await auth.getUser(uid);
      const user = await prisma.user.create({
        data: {
          firebaseUid: uid,
          email: rec.email || null,
          phone: rec.phoneNumber || null,
          displayName: rec.displayName || null,
          accountStatus: 'active',
          phoneVerified: Boolean(rec.phoneNumber),
        },
      });
      req.user = {
        id: user.id,
        firebaseUid: uid,
        email: user.email,
        role: user.role,
        accountStatus: user.accountStatus,
      };
    }
    if (req.user.accountStatus === 'suspended' || req.user.accountStatus === 'deleted') {
      return res.status(403).json({ error: `ACCOUNT_${req.user.accountStatus.toUpperCase()}` });
    }
    return next();
  } catch (e) {
    return res.status(401).json({ error: 'INVALID_TOKEN' });
  }
}

// Resolve a legacy seller (firebaseUid) to a v2 SellerProfile, creating it on
// demand exactly like the migration script does.
async function ensureSellerProfile(firebaseUid, sellerName) {
  if (!firebaseUid) return null;
  const prisma = getPrisma();
  const user = await prisma.user.findUnique({ where: { firebaseUid: String(firebaseUid) } });
  if (!user) return null;
  let profile = await prisma.sellerProfile.findUnique({ where: { userId: user.id }, select: { id: true } });
  if (!profile) {
    const base = (sellerName || 'Duka').toString().toLowerCase().replace(/[^a-z0-9]+/g, '').slice(0, 40) || 'duka';
    profile = await prisma.sellerProfile.create({
      data: { userId: user.id, storeName: sellerName || 'Duka', storeSlug: `${base}-${user.id.slice(0, 8)}` },
      select: { id: true },
    });
  }
  return profile.id;
}

const router = Router();

router.post('/orders/create', optionalAuth, requireSyncedBuyer, async (req, res) => {
  const prisma = getPrisma();
  const body = req.body || {};
  if (body.buyerId && body.buyerId !== req.user.firebaseUid) throw httpError(403, 'FORBIDDEN');

  const productPrice = Math.round(Number(body.productPrice));
  if (!Number.isFinite(productPrice) || productPrice <= 0) throw httpError(400, 'INVALID_PRICE');
  const quantity = Math.max(1, Math.round(Number(body.quantity) || 1));
  const unitPrice = Math.round(Number(body.unitPrice) || productPrice);

  const sellerId = await ensureSellerProfile(body.sellerId, body.sellerName);
  if (!sellerId) throw httpError(404, 'SELLER_NOT_FOUND');

  const order = await prisma.order.create({
    data: {
      orderNumber: generateOrderNumber(),
      buyerId: req.user.id,
      sellerId,
      status: ORDER_STATES.AWAITING_ESCROW_PAYMENT,
      productSnapshot: {
        productId: body.productId || null,
        name: body.productName || 'Mall',
        image: body.productImage || null,
        quantity,
        unitPrice,
      },
      shippingAddressSnapshot: {
        region: body.region || null,
        district: body.district || null,
        ward: body.ward || null,
        street: body.street || null,
        landmarks: body.landmarks || null,
        deliveryType: body.deliveryType || 'local',
        latitude: body.latitude || null,
        longitude: body.longitude || null,
      },
      shippingQuoteSnapshot: { amount: 0, source: 'shop_legacy_compat' },
      productPrice: BigInt(productPrice),
      shippingFee: 0n,
      platformCommission: 0n,
      totalAmount: BigInt(productPrice),
      currency: 'TZS',
      shippingMethod: body.deliveryType || 'local',
      placedAt: new Date(),
    },
  });

  return res.json({ success: true, order: { orderId: order.id } });
});

router.post('/create-marketplace-payment-link', optionalAuth, requireSyncedBuyer, async (req, res) => {
  const prisma = getPrisma();
  const body = req.body || {};
  const orderId = body.existingTransactionId || body.order_id;
  if (!orderId) throw httpError(400, 'ORDER_ID_REQUIRED');
  const order = await prisma.order.findUnique({ where: { id: orderId } });
  if (!order) throw httpError(404, 'ORDER_NOT_FOUND');
  if (order.buyerId !== req.user.id) throw httpError(403, 'FORBIDDEN');

  const phone = String(body.phone || '').trim();
  if (!/^\+?[0-9]{9,15}$/.test(phone)) throw httpError(400, 'INVALID_PHONE');

  let payment;
  try {
    payment = await paymentService.initiatePayment({
      orderId: order.id,
      buyerId: order.buyerId,
      amount: order.totalAmount,
      phoneNumber: phone,
    });
  } catch (e) {
    throw httpError(502, e.message || 'PAYMENT_INITIATION_FAILED');
  }

  return res.json({
    order_id: order.id,
    gatewayFee: 0,
    totalAmount: Number(order.totalAmount),
    message: `Karibisha TZS ${Number(order.totalAmount).toLocaleString()} kupitia ${phone}`,
    providerReference: payment.payment.providerReference || null,
  });
});

router.get('/orders/:orderId/status', optionalAuth, requireSyncedBuyer, async (req, res) => {
  const prisma = getPrisma();
  const order = await prisma.order.findUnique({ where: { id: req.params.orderId } });
  if (!order) throw httpError(404, 'ORDER_NOT_FOUND');
  if (order.buyerId !== req.user.id) throw httpError(403, 'FORBIDDEN');

  return res.json({
    success: true,
    status: LEGACY_STATUS[order.status] || 'pending',
    stepNumber: 0,
    statusColor: order.status === 'failed' || order.status === 'expired' ? '#dc2626' : '#f97316',
    statusHistory: [],
    validTransitions: [],
  });
});

module.exports = router;