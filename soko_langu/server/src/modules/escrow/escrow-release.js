// Escrow release + seller settlement — the single money-out path.
//
// One function is shared by every completion route (OTP verify, QR verify,
// order-service completeOrder for auto-release, dispute FULL_TO_SELLER), so
// the seller is credited exactly one way. The `escrowHolds` row is
// the binding escrow ledger for payment/handover/disputes/refunds, while the
// actual seller credit goes through ledger-service -> commerce-store
// (Firestore wallet), which is idempotent on its own ledger doc id. The
// optional injected `settle` is the hermetic-test seam — production callers
// omit it and settle straight through the Firestore wallet.
const { settleEscrowToSeller } = require('../wallet/ledger-service');

/**
 * Release the order's escrow hold and credit the seller's wallet exactly once.
 * Returns the escrow hold row when a hold existed (released or already
 * released), or null when there was nothing to release.
 */
async function releaseEscrowAndSettle(tx, order, { settle = settleEscrowToSeller, idempotencyKey } = {}) {
  const escrowHold = await tx.escrowHold.findFirst({
    where: { orderId: order.id, status: { in: ['holding', 'disputed'] } },
  });
  if (!escrowHold) return null;

  const releaseKey = idempotencyKey || `settle_${order.id}`;
  const sellerReceives = order.totalAmount - order.platformCommission;

  // Firestore settle is idempotent: a prior run returns alreadySettled:true
  // and moves nothing. Run it first so a crash between the two writes never
  // credits the seller twice; the escrow trace is closed out below either way.
  const outcome = await settle({
    orderId: order.id,
    sellerId: order.sellerId,
    amount: order.totalAmount,
    commission: order.platformCommission,
    idempotencyKey: releaseKey,
  });

  await tx.escrowHold.update({
    where: { id: escrowHold.id },
    data: { status: 'released', releasedAt: new Date() },
  });
  const existing = await tx.escrowTransaction.findFirst({
    where: { escrowHoldId: escrowHold.id, type: 'SETTLEMENT_TO_SELLER' },
  });
  if (!existing) {
    await tx.escrowTransaction.create({
      data: {
        escrowHoldId: escrowHold.id,
        type: 'SETTLEMENT_TO_SELLER',
        amount: sellerReceives,
        referenceId: order.id,
      },
    });
    if (order.platformCommission > 0n) {
      await tx.escrowTransaction.create({
        data: {
          escrowHoldId: escrowHold.id,
          type: 'COMMISSION_TO_PLATFORM',
          amount: order.platformCommission,
          referenceId: order.id,
        },
      });
    }
  }

  return { outcome, escrowHold };
}

module.exports = { releaseEscrowAndSettle };