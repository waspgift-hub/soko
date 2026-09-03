const { getPrisma } = require('../../config/database');
const { acquireLock, releaseLock } = require('../../config/redis');
const { generateOtp, hashOtp, verifyOtp, generateQrPayload } = require('./otp-generator');
const { OrderStateMachine, ORDER_STATES } = require('../orders/order-state-machine');
const { DEFAULT_TIMERS } = require('../orders/order-service');

/**
 * Issue a new OTP credential for an order (active handover).
 * Only allowed when the order is in OTP_PENDING or INSPECTION_PERIOD.
 * Returns the plaintext OTP once (caller delivers it via SMS to the buyer).
 */
async function issueOtp({ orderId, issuedBy }) {
  const prisma = getPrisma();
  const lock = await acquireLock(`otp:${orderId}`, 60);

  try {
    return await prisma.$transaction(async (tx) => {
      const order = await tx.order.findUnique({ where: { id: orderId } });
      if (!order) throw httpError(404, 'ORDER_NOT_FOUND');

      if (![ORDER_STATES.OTP_PENDING, ORDER_STATES.INSPECTION_PERIOD].includes(order.status)) {
        throw httpError(409, `CANNOT_ISSUE_OTP_IN_STATE:${order.status}`);
      }

      // Invalidate any prior active credentials for this order
      await tx.otpCredential.updateMany({
        where: { orderId, status: 'active' },
        data: { status: 'revoked' },
      });

      const otp = generateOtp();
      const { hash, salt } = hashOtp(otp);
      const ttl = process.env.HANDOVER_OTP_TTL_MS
        ? Number(process.env.HANDOVER_OTP_TTL_MS)
        : DEFAULT_TIMERS.OTP_TTL_MS || 30 * 60 * 1000;

      const expiresAt = new Date(Date.now() + ttl);
      const credential = await tx.otpCredential.create({
        data: {
          orderId,
          credentialHash: `${salt}:${hash}`,
          type: 'otp',
          status: 'active',
          expiresAt,
        },
      });

      const qr = generateQrPayload({
        orderId: order.id,
        orderNumber: order.orderNumber,
        token: `${credential.id}`,
        expiresAt,
      });

      return { otp, expiresAt, credentialId: credential.id, qrPayload: qr };
    });
  } finally {
    if (!lock.skipped) await releaseLock(`otp:${orderId}`);
  }
}

/**
 * Atomically verify the OTP and complete the order.
 *
 * This MUST be atomic to guarantee no double-credit:
 *  1. Lock order
 *  2. Verify credential (attempts, expiry, status)
 *  3. Mark credential used
 *  4. Mark order completed
 *  5. Release escrow + create seller settlement ledger entries (idempotent)
 *  6. Create receipt
 *  7. Audit + commit
 * A retry must never double-credit the seller (status/unique guards).
 */
async function verifyOtpAndComplete({ orderId, submittedOtp, verifiedBy }) {
  const prisma = getPrisma();
  const lock = await acquireLock(`complete:${orderId}`, 60);

  try {
    return await prisma.$transaction(async (tx) => {
      const order = await tx.order.findUnique({ where: { id: orderId }, include: { payments: true } });
      if (!order) throw httpError(404, 'ORDER_NOT_FOUND');

      // Layer 4: status priority check prevents double-credit on retry.
      if ([ORDER_STATES.COMPLETED, ORDER_STATES.WALLET_CREDITED].includes(order.status)) {
        return { status: 'ALREADY_COMPLETED', order };
      }
      if (![ORDER_STATES.OTP_PENDING, ORDER_STATES.INSPECTION_PERIOD].includes(order.status)) {
        throw httpError(409, `INVALID_ORDER_STATE:${order.status}`);
      }

      const credential = await tx.otpCredential.findFirst({
        where: { orderId, status: 'active', type: 'otp' },
        orderBy: { createdAt: 'desc' },
      });
      if (!credential) throw httpError(404, 'NO_ACTIVE_CREDENTIAL');

      if (credential.status !== 'active') throw httpError(409, 'CREDENTIAL_ALREADY_USED');
      if (credential.attemptsUsed >= credential.maxAttempts) {
        await tx.otpCredential.update({ where: { id: credential.id }, data: { status: 'expired' } });
        throw httpError(429, 'MAX_ATTEMPTS_EXCEEDED');
      }
      if (new Date(credential.expiresAt) < new Date()) {
        await tx.otpCredential.update({ where: { id: credential.id }, data: { status: 'expired' } });
        throw httpError(410, 'CREDENTIAL_EXPIRED');
      }

      // Verify the submitted OTP against stored hash (constant-time).
      const [salt, storedHash] = String(credential.credentialHash).split(':');
      if (!verifyOtp(submittedOtp, storedHash, salt)) {
        await tx.otpCredential.update({
          where: { id: credential.id },
          data: { attemptsUsed: { increment: 1 } },
        });
        throw httpError(401, 'INVALID_OTP');
      }

      // Mark credential used
      await tx.otpCredential.update({
        where: { id: credential.id },
        data: { status: 'used', verifiedAt: new Date() },
      });

      // Transition order to COMPLETED
      const machine = new OrderStateMachine(order.status);
      machine.transition(ORDER_STATES.COMPLETED, {
        actor: 'buyer',
        actorId: verifiedBy || order.buyerId,
        reason: 'OTP handover verified',
      });

      const updatedOrder = await tx.order.update({
        where: { id: orderId },
        data: { status: ORDER_STATES.COMPLETED, completedAt: new Date() },
      });

      // Idempotent escrow release + settlement (guarded by escrow hold status).
      await releaseEscrowAndSettle(tx, order);

      // Create receipt
      await tx.receipt.create({
        data: {
          orderId,
          purchaserId: order.buyerId,
          sellerId: order.sellerId,
          amount: order.totalAmount,
          currency: 'TZS',
        },
      });

      return { status: 'COMPLETED', order: updatedOrder };
    });
  } finally {
    if (!lock.skipped) await releaseLock(`complete:${orderId}`);
  }
}

// Release escrow and credit seller wallet; guarded so it runs at most once.
async function releaseEscrowAndSettle(tx, order) {
  const escrowHold = await tx.escrowHold.findFirst({
    where: { orderId: order.id, status: 'holding' },
  });
  if (!escrowHold) return;

  const alreadySettled = await tx.walletLedgerEntry.findFirst({
    where: { idempotencyKey: `settlement_${order.id}` },
  });
  if (alreadySettled) return; // no double-credit

  await tx.escrowHold.update({
    where: { id: escrowHold.id },
    data: { status: 'released', releasedAt: new Date() },
  });

  const sellerEntitlement = order.totalAmount - order.platformCommission;

  await tx.escrowTransaction.create({
    data: {
      escrowHoldId: escrowHold.id,
      type: 'SETTLEMENT_TO_SELLER',
      amount: sellerEntitlement,
      referenceId: order.id,
    },
  });

  await tx.escrowTransaction.create({
    data: {
      escrowHoldId: escrowHold.id,
      type: 'COMMISSION_TO_PLATFORM',
      amount: order.platformCommission,
      referenceId: order.id,
    },
  });

  const wallet = await tx.wallet.findUnique({ where: { sellerId: order.sellerId } });
  if (wallet) {
    const balanceAfter = wallet.availableBalance + sellerEntitlement;
    await tx.walletLedgerEntry.create({
      data: {
        walletId: wallet.id,
        type: 'ORDER_SETTLEMENT',
        amount: sellerEntitlement,
        balanceAfter,
        referenceType: 'order',
        referenceId: order.id,
        idempotencyKey: `settlement_${order.id}`,
        description: 'Order settlement from escrow release',
      },
    });
    await tx.wallet.update({
      where: { id: wallet.id },
      data: {
        availableBalance: balanceAfter,
        totalEarned: wallet.totalEarned + sellerEntitlement,
      },
    });
  }
}

function httpError(status, message) {
  const err = new Error(message);
  err.status = status;
  return err;
}

module.exports = { issueOtp, verifyOtpAndComplete };
