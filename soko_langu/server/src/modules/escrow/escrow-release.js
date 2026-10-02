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

// Escrow release reasons. The reason decides WHICH holds are eligible, which
// is the bug this rewrite fixes.
//
// Previously a single lookup selected `['holding','disputed']` for every caller.
// That meant an automatic 14-day release sweep would pick up a DISPUTED hold and
// then have `settleEscrowToSeller` throw ESCROW_DISPUTED, and it also meant
// `resolveDispute(FULL_TO_SELLER)` — which legitimately needs to release a
// disputed hold — went through a path that could not succeed. Both directions
// were broken:
//
//   * auto-release must NEVER touch a disputed hold (would pay out money the
//     buyer is contesting), and
//   * dispute resolution MUST be able to release one, because that is the
//     entire point of ruling FULL_TO_SELLER.
const RELEASE_REASON = {
  /** Buyer confirmed receipt via OTP or QR. */
  BUYER_CONFIRMED: 'buyer_confirmed',
  /** Inspection window elapsed with no dispute and no buyer claim. */
  AUTO_RELEASE: 'auto_release',
  /** An admin ruled FULL_TO_SELLER on a disputed order. */
  DISPUTE_TO_SELLER: 'dispute_to_seller',
};

/**
 * Hold statuses each reason is allowed to release.
 *
 * AUTO_RELEASE and BUYER_CONFIRMED only ever see `holding`. DISPUTE_TO_SELLER
 * is the sole path permitted to see `disputed`, and only because an admin has
 * already made a ruling.
 */
const ALLOWED_HOLD_STATUS = {
  [RELEASE_REASON.BUYER_CONFIRMED]: ['holding'],
  [RELEASE_REASON.AUTO_RELEASE]: ['holding'],
  [RELEASE_REASON.DISPUTE_TO_SELLER]: ['holding', 'disputed'],
};

/**
 * Release the order's escrow hold and credit the seller's wallet exactly once.
 *
 * @param reason One of RELEASE_REASON. Required — there is no safe default,
 *   because "release on sight" is what allowed disputed escrow into the
 *   automatic path.
 * @returns the escrow hold row when a release happened, `null` when nothing was
 *   eligible (e.g. auto-release on a disputed order). A null return is NOT an
 *   error: it means "there was nothing this reason was allowed to release".
 */
async function releaseEscrowAndSettle(
  tx,
  order,
  { settle = settleEscrowToSeller, idempotencyKey, reason } = {},
) {
  const allowed = ALLOWED_HOLD_STATUS[reason];
  if (!allowed) {
    throw new Error(`ESCROW_RELEASE_REASON_REQUIRED:${String(reason)}`);
  }

  const escrowHold = await tx.escrowHold.findFirst({
    where: { orderId: order.id, status: { in: allowed } },
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
    data: {
      status: 'released',
      releasedAt: new Date(),
      releaseReason: reason,
    },
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

module.exports = {
  releaseEscrowAndSettle,
  RELEASE_REASON,
  ALLOWED_HOLD_STATUS,
};