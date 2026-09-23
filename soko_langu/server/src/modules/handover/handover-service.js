const { getStore } = require('../../config/database');
const { acquireLock, releaseLock } = require('../../config/redis');
const { generateOtp, generateToken, hashOtp, verifyOtp, generateQrPayload } = require('./otp-generator');
const { OrderStateMachine, ORDER_STATES } = require('../orders/order-state-machine');
const { releaseEscrowAndSettle } = require('../escrow/escrow-release');
const { syncLegacyOrderStatus } = require('../legacy-compat/presentation-mirror');
const { sendOneSignalNotification } = require('../legacy-compat/notify');

// States from which the buyer can arm the delivery handover (OTP + QR). The
// order moves to OTP_PENDING the first time a credential is issued.
const HANDOVER_ISSUABLE_STATES = [
  ORDER_STATES.READY_TO_DISPATCH,
  ORDER_STATES.DISPATCHED,
  ORDER_STATES.IN_TRANSIT,
  ORDER_STATES.OUT_FOR_DELIVERY,
  ORDER_STATES.DELIVERY_ATTEMPTED,
  ORDER_STATES.ARRIVED,
  ORDER_STATES.DELIVERED,
  ORDER_STATES.INSPECTION_PERIOD,
  ORDER_STATES.OTP_PENDING,
];

const HANDOVER_VERIFIABLE_STATES = [ORDER_STATES.OTP_PENDING, ORDER_STATES.INSPECTION_PERIOD];

async function audit(tx, data) {
  try {
    await tx.auditLog.create({
      data: {
        actorId: data.actorId,
        actorType: data.actorType || 'system',
        action: data.action,
        entityType: data.entityType,
        entityId: data.entityId,
        oldState: data.oldState,
        newState: data.newState,
        requestId: data.requestId,
      },
    });
  } catch (e) {
    console.error('[HANDOVER][AUDIT]', e.message);
  }
}

function credentialTtlMs() {
  if (process.env.HANDOVER_OTP_TTL_MS) return Number(process.env.HANDOVER_OTP_TTL_MS);
  // Lazy require: order-service is mid-load when handover-service first loads
  // (order-service -> dispute-service -> handover-service cycle), so a
  // top-level destructure of DEFAULT_TIMERS would resolve to undefined.
  try {
    return require('../orders/order-service').DEFAULT_TIMERS.OTP_TTL_MS || 30 * 60 * 1000;
  } catch (e) {
    return 30 * 60 * 1000;
  }
}

/**
 * Issue a fresh handover credential set (numeric OTP + QR token) for an order.
 * Idempotent on the order: prior active credentials are revoked and the order
 * is moved to OTP_PENDING, where the buyer's confirmation can complete it.
 */
async function issueOtp({ orderId, issuedBy, userRole, order }) {
  const store = getStore();
  const lock = await acquireLock(`otp:${orderId}`, 60);

  try {
    return await store.$transaction(async (tx) => {
      const current = order ?? (await tx.order.findUnique({ where: { id: orderId } }));
      if (!current) throw httpError(404, 'ORDER_NOT_FOUND');

      assertCanIssueOtp(current, { userId: issuedBy, role: userRole });

      if (!HANDOVER_ISSUABLE_STATES.includes(current.status)) {
        throw httpError(409, `CANNOT_ISSUE_OTP_IN_STATE:${current.status}`);
      }

      if (current.status !== ORDER_STATES.OTP_PENDING) {
        const machine = new OrderStateMachine(current.status);
        machine.transition(ORDER_STATES.OTP_PENDING, {
          actor: userRole === 'admin' || userRole === 'super_admin' ? 'admin' : 'buyer',
          actorId: issuedBy,
          reason: 'Delivery handover armed',
        });
        await tx.order.update({
          where: { id: orderId },
          data: { status: ORDER_STATES.OTP_PENDING, statusChangedBy: issuedBy },
        });
      }

      // Invalidate any prior active credentials for this order
      await tx.otpCredential.updateMany({
        where: { orderId, status: 'active' },
        data: { status: 'revoked' },
      });

      const ttl = credentialTtlMs();
      const expiresAt = new Date(Date.now() + ttl);

      const otp = generateOtp();
      const { hash: otpH, salt: otpSalt } = hashOtp(otp);
      const otpCredential = await tx.otpCredential.create({
        data: {
          orderId,
          credentialHash: `${otpSalt}:${otpH}`,
          type: 'otp',
          status: 'active',
          expiresAt,
        },
      });

      const qrPlain = generateToken();
      const { hash: qrH, salt: qrSalt } = hashOtp(qrPlain);
      const qrCredential = await tx.otpCredential.create({
        data: {
          orderId,
          credentialHash: `${qrSalt}:${qrH}`,
          type: 'qr',
          status: 'active',
          expiresAt,
        },
      });

      // The QR token self-describes its credential: <id>:<plain> so the verify
      // endpoint does a single lookup + constant-time compare.
      const qrToken = `${qrCredential.id}:${qrPlain}`;
      const qrPayload = generateQrPayload({
        orderId: current.id,
        orderNumber: current.orderNumber,
        token: qrToken,
        expiresAt,
      });

      await audit(tx, {
        actorId: issuedBy,
        actorType: 'user',
        action: 'HANDOVER_CREDENTIALS_ISSUED',
        entityType: 'order',
        entityId: orderId,
        oldState: { status: current.status },
        newState: { status: ORDER_STATES.OTP_PENDING },
      });

      return { otp, qrToken, qrPayload, expiresAt, credentialId: otpCredential.id, qrCredentialId: qrCredential.id };
    });
  } finally {
    if (!lock.skipped) await releaseLock(`otp:${orderId}`);
  }
}

/**
 * Atomically verify an OTP and complete the order.
 *
 * Read-modify-write under one store $transaction + one Redis lock so a retry
 * can never double-credit: status-priority guard, single-use credential,
 * escrow release + Firestore wallet settle (both idempotent), then COMPLETED.
 */
async function verifyOtpAndComplete({ orderId, submittedOtp, verifiedBy }) {
  const store = getStore();
  const lock = await acquireLock(`complete:${orderId}`, 60);

  try {
    const result = await store.$transaction(async (tx) => {
      const order = await tx.order.findUnique({ where: { id: orderId } });
      if (!order) throw httpError(404, 'ORDER_NOT_FOUND');

      if ([ORDER_STATES.COMPLETED, ORDER_STATES.WALLET_CREDITED].includes(order.status)) {
        return { status: 'ALREADY_COMPLETED', order };
      }
      if (!HANDOVER_VERIFIABLE_STATES.includes(order.status)) {
        throw httpError(409, `INVALID_ORDER_STATE:${order.status}`);
      }

      const credential = await findActiveCredential(tx, orderId, 'otp');
      if (!credential) throw httpError(404, 'NO_ACTIVE_CREDENTIAL');
      assertCredentialUsable(tx, credential);

      const [salt, storedHash] = String(credential.credentialHash).split(':');
      if (!verifyOtp(submittedOtp, storedHash, salt)) {
        await tx.otpCredential.update({
          where: { id: credential.id },
          data: { attemptsUsed: { increment: 1 } },
        });
        throw httpError(401, 'INVALID_OTP');
      }

      await tx.otpCredential.update({
        where: { id: credential.id },
        data: { status: 'used', verifiedAt: new Date() },
      });

      return completeAfterCredentialVerified(tx, order, verifiedBy, 'OTP');
    });

    await syncLegacyOrderStatus(result.order);
    if (result.status === 'COMPLETED') {
      await notifyOrderCompleted(result.order);
    }
    return result;
  } finally {
    if (!lock.skipped) await releaseLock(`complete:${orderId}`);
  }
}

/**
 * Verify the QR handover credential (token from the QR payload) and complete
 * the order through the exact same completion path as OTP.
 */
async function verifyQrAndComplete({ orderId, token, verifiedBy }) {
  const store = getStore();
  const lock = await acquireLock(`complete:${orderId}`, 60);

  try {
    const result = await store.$transaction(async (tx) => {
      const order = await tx.order.findUnique({ where: { id: orderId } });
      if (!order) throw httpError(404, 'ORDER_NOT_FOUND');

      if ([ORDER_STATES.COMPLETED, ORDER_STATES.WALLET_CREDITED].includes(order.status)) {
        return { status: 'ALREADY_COMPLETED', order };
      }
      if (!HANDOVER_VERIFIABLE_STATES.includes(order.status)) {
        throw httpError(409, `INVALID_ORDER_STATE:${order.status}`);
      }

      const credential = await resolveQrCredential(tx, orderId, token);
      if (!credential) throw httpError(404, 'NO_ACTIVE_CREDENTIAL');
      await assertCredentialUsable(tx, credential);

      const [salt, storedHash] = String(credential.credentialHash).split(':');
      if (!verifyOtp(plainToken(token), storedHash, salt)) {
        await tx.otpCredential.update({
          where: { id: credential.id },
          data: { attemptsUsed: { increment: 1 } },
        });
        throw httpError(401, 'INVALID_TOKEN');
      }

      await tx.otpCredential.update({
        where: { id: credential.id },
        data: { status: 'used', verifiedAt: new Date() },
      });

      return completeAfterCredentialVerified(tx, order, verifiedBy, 'QR');
    });

    await syncLegacyOrderStatus(result.order);
    if (result.status === 'COMPLETED') {
      await notifyOrderCompleted(result.order);
    }
    return result;
  } finally {
    if (!lock.skipped) await releaseLock(`complete:${orderId}`);
  }
}

// Shared settlement-authorized completion: DELIVERY_CONFIRMED -> release -> COMPLETED.
// Exported for the hermetic flow test; production callers use verifyOtpAndComplete
// / verifyQrAndComplete, which run the same chain under their Redis locks.
async function completeAfterCredentialVerified(tx, order, verifiedBy, credentialType = 'OTP', { settle } = {}) {
  if (!HANDOVER_VERIFIABLE_STATES.includes(order.status)) {
    throw httpError(409, `INVALID_ORDER_STATE:${order.status}`);
  }
  const actor = order.buyerId === verifiedBy ? 'buyer' : 'system';

  const stepOne = new OrderStateMachine(order.status);
  stepOne.transition(ORDER_STATES.DELIVERY_CONFIRMED, {
    actor,
    actorId: verifiedBy || order.buyerId,
    reason: `${credentialType} handover verified`,
  });
  await tx.order.update({
    where: { id: order.id },
    data: { status: ORDER_STATES.DELIVERY_CONFIRMED, statusChangedBy: verifiedBy || order.buyerId },
  });

  const escrowHold = settle
    ? await releaseEscrowAndSettle(tx, order, { settle })
    : await releaseEscrowAndSettle(tx, order);

  const stepTwo = new OrderStateMachine(ORDER_STATES.DELIVERY_CONFIRMED);
  stepTwo.transition(ORDER_STATES.COMPLETED, { actor: 'system', reason: `${credentialType} handover verified` });
  const updatedOrder = await tx.order.update({
    where: { id: order.id },
    data: { status: ORDER_STATES.COMPLETED, completedAt: new Date(), statusChangedBy: verifiedBy || order.buyerId },
  });

  await tx.receipt.create({
    data: {
      orderId: order.id,
      purchaserId: order.buyerId,
      sellerId: order.sellerId,
      amount: order.totalAmount,
      currency: order.currency,
    },
  });

  await audit(tx, {
    actorId: verifiedBy || order.buyerId,
    actorType: 'user',
    action: 'ORDER_COMPLETED',
    entityType: 'order',
    entityId: order.id,
    oldState: { status: order.status },
    newState: { status: ORDER_STATES.COMPLETED, credentialType },
  });

  return { status: 'COMPLETED', order: updatedOrder, escrowHold, verifiedBy: verifiedBy || order.buyerId };
}

async function findActiveCredential(tx, orderId, type) {
  return tx.otpCredential.findFirst({
    where: { orderId, status: 'active', type },
    orderBy: { createdAt: 'desc' },
  });
}

async function assertCredentialUsable(tx, credential) {
  if (credential.status !== 'active') throw httpError(409, 'CREDENTIAL_ALREADY_USED');
  if (credential.attemptsUsed >= credential.maxAttempts) {
    await tx.otpCredential.update({ where: { id: credential.id }, data: { status: 'expired' } });
    throw httpError(429, 'MAX_ATTEMPTS_EXCEEDED');
  }
  if (new Date(credential.expiresAt) < new Date()) {
    await tx.otpCredential.update({ where: { id: credential.id }, data: { status: 'expired' } });
    throw httpError(410, 'CREDENTIAL_EXPIRED');
  }
}

// A QR token is "<credentialId>:<plain>"; legacy QRs carry only the credential
// id, in which case the whole token is treated as the plain secret.
function plainToken(token) {
  const s = String(token || '');
  const idx = s.indexOf(':');
  return idx === -1 ? s : s.slice(idx + 1);
}

// Resolve the qr credential: exact id when the token self-describes it, else a
// hash-match against the order's active QR credentials.
async function resolveQrCredential(tx, orderId, token) {
  const s = String(token || '');
  const idx = s.indexOf(':');
  if (idx !== -1) {
    const credential = await tx.otpCredential.findFirst({
      where: { id: s.slice(0, idx), orderId, type: 'qr' },
    });
    return credential && credential.status === 'active' ? credential : null;
  }
  const actives = await tx.otpCredential.findMany({
    where: { orderId, status: 'active', type: 'qr' },
    orderBy: { createdAt: 'desc' },
  });
  for (const credential of actives) {
    const [salt, hash] = String(credential.credentialHash).split(':');
    if (verifyOtp(s, hash, salt)) return credential;
  }
  return null;
}

// Buyer/seller completion notice (in-app row + push). Best-effort: never fails
// the finance transaction it follows.
async function notifyOrderCompleted(order) {
  const store = getStore();
  try {
    const [buyer, sellerProfile] = await Promise.all([
      store.user.findUnique({ where: { id: order.buyerId } }),
      store.sellerProfile.findUnique({ where: { id: order.sellerId }, select: { userId: true } }),
    ]);
    const seller = sellerProfile ? await store.user.findUnique({ where: { id: sellerProfile.userId } }) : null;

    if (buyer) {
      const title = 'Bidhaa Imefika';
      const body = `Oda ${order.orderNumber} imekamilika. Karibu tena Soko Vibe.`;
      const data = { type: 'completed', orderId: order.id };
      try {
        await store.notification.create({ data: { userId: buyer.id, type: 'completed', title, body, data } });
        await sendOneSignalNotification(buyer.firebaseUid, title, body, data);
      } catch (e) {
        console.error('[HANDOVER][NOTIFY-BUYER]', e.message);
      }
    }
    if (seller) {
      const title = 'Pesa Zimeingia Wallet';
      const body = `Oda ${order.orderNumber}: escrow imetolewa, mauzo yameongezwa kwenye wallet yako.`;
      const data = { type: 'wallet_credited', orderId: order.id };
      try {
        await store.notification.create({ data: { userId: seller.id, type: 'wallet_credited', title, body, data } });
        await sendOneSignalNotification(seller.firebaseUid, title, body, data);
      } catch (e) {
        console.error('[HANDOVER][NOTIFY-SELLER]', e.message);
      }
    }
  } catch (e) {
    console.error('[HANDOVER][NOTIFY]', order.id, e.message);
  }
}

function httpError(status, message) {
  const err = new Error(message);
  err.status = status;
  return err;
}

/**
 * Handover OTP may only be issued by the order's buyer (they confirm arrival
 * and receive the credential, mirroring the legacy Firestore OTP visibility —
 * the buyer alone sees it and shares it with the courier/seller) or by an
 * admin. Pure so it can be unit-tested without a transaction.
 */
function assertCanIssueOtp(order, { userId, role }) {
  if (order.buyerId === userId) return;
  if (role === 'admin' || role === 'super_admin') return;
  throw httpError(403, 'FORBIDDEN');
}

module.exports = {
  issueOtp,
  verifyOtpAndComplete,
  verifyQrAndComplete,
  releaseEscrowAndSettle,
  completeAfterCredentialVerified,
  assertCanIssueOtp,
  HANDOVER_ISSUABLE_STATES,
  HANDOVER_VERIFIABLE_STATES,
};