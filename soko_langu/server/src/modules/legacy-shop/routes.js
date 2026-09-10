// Legacy web-shop compat: serves the shop SPA's existing endpoints with the
// SAME response shapes, but executes against the v2 Postgres order/pay engine
// (BigInt escrow, ClickPesa v2 webhook, OTP-gated release). Buyers are
// entity-synced on first authenticated request so legacy Firebase users get a
// users row (the v2 `users` table previously held only admins).
//
// Guest checkout (web): unauthenticated buyers can place orders with just a
// name + phone. The server resolves a synthetic `guest:<phone>` user — the
// money is gated by the USSD payment itself, and the phone check on every
// follow-up call (status/list/payment-link) prevents order tampering.
//
// Firestore mirror (app parity): each new Postgres order is mirrored into the
// legacy `orders` + `transactions` collections using the legacy document shape
// so existing Flutter buyer/seller screens (quote, dispatch, receipt) keep
// showing web orders with zero app release. Web orders' money stays 100% in
// Postgres — the mirror is read-only presentation data, never a second payout
// path (legacy money flows key on `transactions` escrow fields which v2 never
// writes on mirrored docs).
const { Router } = require('express');
const { FieldValue } = require('firebase-admin/firestore');
const { getPrisma } = require('../../config/database');
const { getFirebaseAuth, getFirebaseFirestore } = require('../../config/firebase');
const { optionalAuth } = require('../../middleware/auth');
const { paymentService } = require('../payments/payment-service');
const { generateOrderNumber } = require('../orders/order-service');
const { ORDER_STATES } = require('../orders/order-state-machine');
const { computeSellerParity } = require('../../utils/commission-parity');

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

// Legacy (Firestore) doc shape for a mirrored order. Both the `orders` and
// `transactions` collections use these exact field names in the Flutter app.
function buildLegacyMirror(order, body) {
  const productPrice = Number(order.productPrice);
  // Soko Vibe charges no fees; ClickPesa's own charges are deducted by
  // ClickPesa outside this ledger, so the mirror shows zero platform/ClickPesa
  // lines and the full amount flowing to the seller.
  const platformFee = 0;
  const clickpesaFee = 0;
  return {
    orderId: order.id,
    status: LEGACY_STATUS[order.status] || 'pending',
    escrowStatus: 'none',
    buyerId: body.buyerId || null, // Firebase uid where available
    sellerId: body.sellerId || null,
    buyerName: body.buyerName || null,
    buyerPhone: body.buyerPhone || null,
    sellerName: body.sellerName || null,
    sellerPhone: body.sellerPhone || null,
    productId: body.productId || null,
    productName: body.productName || 'Mall',
    productImage: body.productImage || null,
    productPrice,
    quantity: Math.max(1, Math.round(Number(body.quantity) || 1)),
    shippingCost: 0,
    platformFee,
    clickpesaFee,
    totalAmount: Number(order.totalAmount),
    region: body.region || null,
    district: body.district || null,
    ward: body.ward || null,
    street: body.street || null,
    landmarks: body.landmarks || null,
    deliveryType: body.deliveryType || 'local',
    sourceV2: true,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

// Best-effort mirror so a transient Firestore hiccup never fails the API call.
async function mirrorOrderToLegacy(order, body) {
  try {
    const db = getFirebaseFirestore();
    if (!db) return;
    const doc = buildLegacyMirror(order, body);
    await db.collection('orders').doc(order.id).set(doc, { merge: true });
    await db.collection('transactions').doc(order.id).set(doc, { merge: true });
  } catch (e) {
    console.error('[SHOP-SYNC] Firestore mirror failed:', e.message);
  }
}

async function mirrorStatusToLegacy(order) {
  try {
    const db = getFirebaseFirestore();
    if (!db) return;
    const status = LEGACY_STATUS[order.status] || 'pending';
    await db.collection('orders').doc(order.id).set({ status, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    await db.collection('transactions').doc(order.id).set({ status, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  } catch (e) {
    console.error('[SHOP-SYNC] status mirror failed:', e.message);
  }
}

// Attach/sync the shop buyer into the v2 `users` table. Authenticated requests
// (Firebase ID token) map to their existing/auto-created users row; guest
// requests resolve to (or create) a synthetic `guest:<phone>` buyer whose phone
// must match on every follow-up call to the same order.
async function resolveShopBuyer(req, res, next) {
  try {
    if (req.firebaseUid) {
      if (!req.user) {
        const prisma = getPrisma();
        const rec = await getFirebaseAuth().getUser(req.firebaseUid);
        req.user = await prisma.user.create({
          data: {
            firebaseUid: req.firebaseUid,
            email: rec.email || null,
            phone: rec.phoneNumber || null,
            displayName: rec.displayName || null,
            accountStatus: 'active',
            phoneVerified: Boolean(rec.phoneNumber),
          },
          select: { id: true, role: true, accountStatus: true },
        });
      }
    } else {
      const prisma = getPrisma();
      const body = req.body || {};
      const q = req.query || {};
      const phone = String(body.buyerPhone || q.buyerPhone || body.phone || q.phone || '').trim();
      const candidateId = String(body.buyerId || q.buyerId || '').trim();
      let user = null;
      if (candidateId) {
        user = await prisma.user.findUnique({ where: { id: candidateId }, select: { id: true, firebaseUid: true, phone: true, role: true, accountStatus: true } });
        if (
          !user ||
          !String(user.firebaseUid || '').startsWith('guest:') ||
          !phone ||
          String(user.phone || '').replace(/\D/g, '') !== phone.replace(/\D/g, '')
        ) {
          return res.status(403).json({ error: 'FORBIDDEN' });
        }
      } else {
        if (!/^\+?[0-9]{9,15}$/.test(phone) || !body.buyerName) {
          return res.status(401).json({ error: 'AUTH_REQUIRED' });
        }
        const firebaseUid = `guest:${phone.replace(/\D/g, '')}`;
        user = await prisma.user.findUnique({ where: { firebaseUid }, select: { id: true, firebaseUid: true, phone: true, role: true, accountStatus: true } });
        if (!user) {
          user = await prisma.user.create({
            data: {
              firebaseUid,
              phone,
              displayName: String(body.buyerName || '').slice(0, 80) || null,
              accountStatus: 'active',
              phoneVerified: false,
              role: 'buyer',
            },
            select: { id: true, firebaseUid: true, phone: true, role: true, accountStatus: true },
          });
        }
      }
      req.user = { id: user.id, firebaseUid: user.firebaseUid, email: null, role: user.role, accountStatus: user.accountStatus };
    }
    if (req.user.accountStatus === 'suspended' || req.user.accountStatus === 'deleted') {
      return res.status(403).json({ error: `ACCOUNT_${req.user.accountStatus.toUpperCase()}` });
    }
    return next();
  } catch (e) {
    return res.status(401).json({ error: 'AUTH_REQUIRED' });
  }
}

// Resolve a legacy seller (firebaseUid) to a v2 SellerProfile, creating it on
// demand exactly like the migration script does.
async function ensureSellerProfile(firebaseUid, sellerName, sellerPhone) {
  if (!firebaseUid) return null;
  const prisma = getPrisma();
  const user = await prisma.user.findUnique({ where: { firebaseUid: String(firebaseUid) } });
  if (!user) return null;
  let profile = await prisma.sellerProfile.findUnique({ where: { userId: user.id }, select: { id: true } });
  if (!profile) {
    const base = (sellerName || 'Duka').toString().toLowerCase().replace(/[^a-z0-9]+/g, '').slice(0, 40) || 'duka';
    profile = await prisma.sellerProfile.create({
      data: {
        userId: user.id,
        storeName: sellerName || 'Duka',
        storeSlug: `${base}-${user.id.slice(0, 8)}`,
        sellerStatus: 'active',
      },
      select: { id: true },
    });
    if (sellerPhone) {
      await prisma.user.update({ where: { id: user.id }, data: { phone: String(sellerPhone) } }).catch(() => {});
    }
  }
  return profile.id;
}

const router = Router();

router.post('/orders/create', optionalAuth, resolveShopBuyer, async (req, res) => {
  const prisma = getPrisma();
  const body = req.body || {};
  if (body.buyerId && body.buyerId !== req.user.firebaseUid) throw httpError(403, 'FORBIDDEN');

  const productPrice = Math.round(Number(body.productPrice));
  if (!Number.isFinite(productPrice) || productPrice <= 0) throw httpError(400, 'INVALID_PRICE');
  const quantity = Math.max(1, Math.round(Number(body.quantity) || 1));
  const unitPrice = Math.round(Number(body.unitPrice) || productPrice);

  const sellerId = await ensureSellerProfile(body.sellerId, body.sellerName, body.sellerPhone);
  if (!sellerId) throw httpError(404, 'SELLER_NOT_FOUND');

  const { commission, totalAmount } = computeSellerParity(BigInt(productPrice), 0n);

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
      platformCommission: commission,
      totalAmount,
      currency: 'TZS',
      shippingMethod: body.deliveryType || 'local',
      placedAt: new Date(),
    },
  });

  // App-parity mirror: legacy Flutter screens read Firestore orders/transactions.
  if (body.buyerPhone || body.sellerId) {
    await mirrorOrderToLegacy(order, { ...body, buyerPhone: body.buyerPhone || req.user.phone || null });
  }

  return res.json({ success: true, order: { orderId: order.id, buyerId: req.user.id } });
});

router.post('/create-marketplace-payment-link', optionalAuth, resolveShopBuyer, async (req, res) => {
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

router.get('/orders/:orderId/status', optionalAuth, resolveShopBuyer, async (req, res) => {
  const prisma = getPrisma();
  const order = await prisma.order.findUnique({ where: { id: req.params.orderId } });
  if (!order) throw httpError(404, 'ORDER_NOT_FOUND');
  if (order.buyerId !== req.user.id) throw httpError(403, 'FORBIDDEN');

  // Keep the legacy mirror's status/paidAt in step with the Postgres truth.
  await mirrorStatusToLegacy(order);

  return res.json({
    success: true,
    status: LEGACY_STATUS[order.status] || 'pending',
    stepNumber: 0,
    statusColor: order.status === 'failed' || order.status === 'expired' ? '#dc2626' : '#f97316',
    statusHistory: [],
    validTransitions: [],
  });
});

// Guest order list: the guest buyer (created at checkout) can pull their
// Postgres orders by buyerId + phone; used by the web shop's My Orders page
// when the buyer checked out without signing in.
router.get('/orders/guest/list', optionalAuth, resolveShopBuyer, async (req, res) => {
  const prisma = getPrisma();
  const orders = await prisma.order.findMany({
    where: { buyerId: req.user.id },
    orderBy: { createdAt: 'desc' },
    take: 100,
  });
  const sellerIds = Array.from(new Set(orders.map((o) => o.sellerId).filter(Boolean)));
  const sellers = sellerIds.length
    ? await prisma.sellerProfile.findMany({ where: { id: { in: sellerIds } }, select: { id: true, storeName: true } })
    : [];
  const sellerNames = new Map(sellers.map((s) => [s.id, s.storeName]));
  const addr = (o) => (o.shippingAddressSnapshot && typeof o.shippingAddressSnapshot === 'object' ? o.shippingAddressSnapshot : {});
  return res.json({
    success: true,
    data: orders.map((o) => {
      const a = addr(o);
      const ps = o.productSnapshot && typeof o.productSnapshot === 'object' ? o.productSnapshot : {};
      return {
        orderId: o.id,
        status: LEGACY_STATUS[o.status] || 'pending',
        productName: ps.name || 'Mall',
        productImage: ps.image || null,
        productPrice: Number(o.productPrice),
        quantity: Math.max(1, Math.round(Number(ps.quantity) || 1)),
        unitPrice: Number(ps.unitPrice) || Number(o.productPrice),
        totalAmount: Number(o.totalAmount),
        region: a.region || null,
        district: a.district || null,
        ward: a.ward || null,
        street: a.street || null,
        deliveryType: a.deliveryType || 'local',
        sellerName: sellerNames.get(o.sellerId) || null,
        createdAt: o.createdAt,
      };
    }),
  });
});

module.exports = router;
module.exports.buildLegacyMirror = buildLegacyMirror;
module.exports.LEGACY_STATUS = LEGACY_STATUS;
module.exports.resolveShopBuyer = resolveShopBuyer;