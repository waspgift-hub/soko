// Who is allowed to advance an order to DELIVERED.
//
// DELIVERED is not a cosmetic status: it stamps `deliveredAt`, and that is the
// clock the auto-release sweep reads before it releases escrow. A seller who can
// self-declare delivery therefore controls the payout timer for a parcel they may
// never have handed over, which defeats the buyer protection the escrow exists
// for. The independent party in the chain of custody is the courier, so delivery
// is attested by the assigned courier or by an admin acting on evidence.
//
// Pure so the v1 controller, the service layer and the tests share one rule.
function httpError(status, message) {
  const err = new Error(message);
  err.status = status;
  return err;
}

/**
 * Maps a user role to the state-machine actor allowed to attest delivery.
 * Sellers and buyers get `null`: the buyer's path is the OTP/QR handover, not
 * this transition, and a seller may never attest their own delivery.
 *
 * @returns {'courier'|'admin'|null}
 */
function deliveryActorFor(role) {
  if (role === 'admin' || role === 'super_admin') return 'admin';
  if (role === 'courier') return 'courier';
  return null;
}

/**
 * Authorize a delivery attestation.
 *
 * @param {object} order order row (needs `courierId` for the assignment check)
 * @param {{userId?: string, role?: string}} actor
 * @returns {'courier'|'admin'} the state-machine actor to record
 * @throws {Error & {status:number}} 403 when the caller may not attest delivery
 */
function assertCanMarkDelivered(order, { userId, role } = {}) {
  const actor = deliveryActorFor(role);
  if (!actor) throw httpError(403, 'SELLER_CANNOT_MARK_DELIVERED');

  // Bind the courier to the parcel. Orders dispatched before assignment was
  // recorded carry no `courierId`; those stay actionable so the live fleet is
  // not locked out mid-migration, but every assignment written from now on is
  // binding and a different courier is refused.
  if (actor === 'courier' && order.courierId && order.courierId !== userId) {
    throw httpError(403, 'NOT_ASSIGNED_COURIER');
  }
  return actor;
}

module.exports = { deliveryActorFor, assertCanMarkDelivered };
